// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title OrderManager
 * @notice The goal of this contract is to re-balance the USDN protocol when there is too much
 * trading expo available in the USDN Protocol
 * This contract will manage only one position with enough trading expo to re-balance the protocol after liquidations
 * and close/open again with new and existing funds
 */
contract OrderManager is Ownable, IOrderManager {
    using SafeERC20 for IERC20Metadata;

    /// @inheritdoc IOrderManager
    uint256 public constant MULTIPLIER_DECIMALS = 18;

    /// @notice The address of the asset used by the USDN protocol
    IERC20Metadata internal immutable _asset;

    /// @notice The address of the USDN protocol
    IUsdnProtocol internal immutable _usdnProtocol;

    /// @notice The number of time the order manager position got liquidated
    uint128 internal _liquidationCount;

    /// @notice The current position version (0 means no position open)
    uint128 internal _positionVersion;

    /// @notice The funds an address deposited in this contract
    mapping(address => UserDeposit) internal _userDeposit;

    /**
     * @notice The data for the specific version of the position
     * @dev position iteration => position version => position data
     */
    mapping(uint256 => mapping(uint256 => PositionData)) internal _positionData;

    /// @param usdnProtocol The address of the USDN protocol
    constructor(IUsdnProtocol usdnProtocol) Ownable(msg.sender) {
        _usdnProtocol = usdnProtocol;
        _asset = usdnProtocol.getAsset();
    }

    /// @inheritdoc IOrderManager
    function getUsdnProtocol() external view returns (IUsdnProtocol) {
        return _usdnProtocol;
    }

    /// @inheritdoc IOrderManager
    function getCurrentPositionVersion() external view returns (uint128) {
        return _positionVersion;
    }

    /// @inheritdoc IOrderManager
    function getLiquidationCount() external view returns (uint128) {
        return _liquidationCount;
    }

    /// @inheritdoc IOrderManager
    function getUserDepositData(address user) external view returns (UserDeposit memory userDeposit_) {
        userDeposit_ = _userDeposit[user];
    }

    /// @inheritdoc IOrderManager
    function depositAssets(uint128 amount, address to) external {
        if (to == address(0)) {
            revert OrderManagerInvalidAddressTo();
        }

        uint128 currentVersion = _positionVersion;
        UserDeposit memory depositData = _userDeposit[to];
        if (depositData.entryPositionVersion < currentVersion) {
            revert OrderManagerUserNotPending();
        }

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        // TODO check if cheaper to only write what's needed (should not)
        _userDeposit[to] = UserDeposit({ amount: amount + depositData.amount, entryPositionVersion: currentVersion });

        emit AssetsDeposited(amount, to, currentVersion);
    }

    /// @inheritdoc IOrderManager
    function withdrawPendingAssets(uint128 amount, address to) external {
        if (to == address(0)) {
            revert OrderManagerInvalidAddressTo();
        }

        UserDeposit memory depositData = _userDeposit[msg.sender];
        if (depositData.amount == 0 || depositData.entryPositionVersion < _positionVersion) {
            revert OrderManagerUserNotPending();
        }

        if (depositData.amount < amount) {
            revert OrderManagerNotEnoughAssetsToWithdraw();
        }

        _asset.safeTransfer(to, amount);

        if (amount == depositData.amount) {
            delete _userDeposit[msg.sender];
        } else {
            _userDeposit[msg.sender].amount -= amount;
        }

        emit PendingAssetsWithdrawn(amount, to);
    }
}
