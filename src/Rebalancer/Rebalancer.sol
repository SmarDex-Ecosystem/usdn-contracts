// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IRebalancer } from "src/interfaces/Rebalancer/IRebalancer.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title Rebalancer
 * @notice The goal of this contract is to re-balance the USDN protocol when liquidations reduce the long trading expo
 * It will manage only one position with enough trading expo to re-balance the protocol after liquidations
 * and close/open again with new and existing funds when the imbalance reaches a certain threshold
 */
contract Rebalancer is Ownable, IRebalancer {
    using SafeERC20 for IERC20Metadata;

    /// @notice Modifier to check if the caller is the USDN protocol or the owner
    modifier onlyAdmin() {
        if (msg.sender != address(_usdnProtocol) && msg.sender != owner()) {
            revert RebalancerUnauthorized();
        }
        _;
    }

    /// @notice Modifier to check if the caller is the USDN protocol
    modifier onlyProtocol() {
        if (msg.sender != address(_usdnProtocol)) {
            revert RebalancerUnauthorized();
        }
        _;
    }

    /// @notice The address of the asset used by the USDN protocol
    IERC20Metadata internal immutable _asset;

    /// @notice The address of the USDN protocol
    IUsdnProtocol internal immutable _usdnProtocol;

    /// @notice The current position version
    uint128 internal _positionVersion;

    /// @notice The amount of assets waiting to be used in the next version of the position
    uint256 internal _pendingAssetsAmount;

    /// @notice The minimum amount of assets to be deposited by a user
    uint256 internal _minAssetDeposit;

    /// @notice The data about the assets deposited in this contract by users
    mapping(address => UserDeposit) internal _userDeposit;

    /// @param usdnProtocol The address of the USDN protocol
    constructor(IUsdnProtocol usdnProtocol) Ownable(msg.sender) {
        _usdnProtocol = usdnProtocol;
        _asset = usdnProtocol.getAsset();
        _minAssetDeposit = usdnProtocol.getMinLongPosition();
    }

    /// @inheritdoc IRebalancer
    function getAsset() external view returns (IERC20Metadata) {
        return _asset;
    }

    /// @inheritdoc IRebalancer
    function getUsdnProtocol() external view returns (IUsdnProtocol) {
        return _usdnProtocol;
    }

    /// @inheritdoc IRebalancer
    function getPendingAssetsAmount() external view returns (uint256) {
        return _pendingAssetsAmount;
    }

    /// @inheritdoc IRebalancer
    function getPositionVersion() external view returns (uint128) {
        return _positionVersion;
    }

    /// @inheritdoc IRebalancer
    function getMinAssetDeposit() external view returns (uint256) {
        return _minAssetDeposit;
    }

    /// @inheritdoc IRebalancer
    function setMinAssetDeposit(uint256 minAssetDeposit) external onlyAdmin {
        if (_usdnProtocol.getMinLongPosition() > minAssetDeposit) {
            revert RebalancerInvalidMinAssetDeposit();
        }

        _minAssetDeposit = minAssetDeposit;
        emit MinAssetDepositUpdated(minAssetDeposit);
    }

    /// @inheritdoc IRebalancer
    function getUserDepositData(address user) external view returns (UserDeposit memory) {
        return _userDeposit[user];
    }

    /// @inheritdoc IRebalancer
    function depositAssets(uint128 amount, address to) external {
        if (to == address(0)) {
            revert RebalancerInvalidAddressTo();
        }
        if (amount == 0) {
            revert RebalancerInvalidAmount();
        }

        uint128 positionVersion = _positionVersion;
        UserDeposit memory depositData = _userDeposit[to];

        if (depositData.amount == 0) {
            if (amount < _minAssetDeposit) {
                revert RebalancerInsufficientAmount();
            }
        } else {
            if (depositData.entryPositionVersion <= positionVersion) {
                revert RebalancerUserNotPending();
            }
        }

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        depositData.entryPositionVersion = positionVersion + 1;
        depositData.amount += amount;
        _userDeposit[to] = depositData;
        _pendingAssetsAmount += amount;

        emit AssetsDeposited(amount, to, positionVersion + 1);
    }

    /// @inheritdoc IRebalancer
    function withdrawPendingAssets(uint128 amount, address to) external {
        if (to == address(0)) {
            revert RebalancerInvalidAddressTo();
        }
        if (amount == 0) {
            revert RebalancerInvalidAmount();
        }

        UserDeposit memory depositData = _userDeposit[msg.sender];

        if (depositData.amount == 0 || depositData.entryPositionVersion <= _positionVersion) {
            revert RebalancerUserNotPending();
        }
        if (depositData.amount < amount) {
            revert RebalancerWithdrawAmountTooLarge();
        }

        uint128 newAmount = depositData.amount;
        unchecked {
            newAmount -= amount;
            _pendingAssetsAmount -= amount;
        }
        if (newAmount == 0) {
            // If the new amount after the withdraw is equal to 0, delete the mapping entry
            delete _userDeposit[msg.sender];
        } else {
            if (newAmount < _minAssetDeposit) {
                revert RebalancerInsufficientAmount();
            }
            // If not, the amount is updated
            _userDeposit[msg.sender].amount = newAmount;
        }

        _asset.safeTransfer(to, amount);

        emit PendingAssetsWithdrawn(msg.sender, amount, to);
    }
}
