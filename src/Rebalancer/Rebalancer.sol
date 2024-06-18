// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IOwnershipCallback } from "../interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancer } from "../interfaces/Rebalancer/IRebalancer.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { PositionId, PreviousActionsData } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title Rebalancer
 * @notice The goal of this contract is to re-balance the USDN protocol when liquidations reduce the long trading expo
 * It will manage only one position with enough trading expo to re-balance the protocol after liquidations
 * and close/open again with new and existing funds when the imbalance reaches a certain threshold
 */
contract Rebalancer is Ownable2Step, ERC165, IOwnershipCallback, IRebalancer {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;

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

    /// @inheritdoc IRebalancer
    uint256 public constant MULTIPLIER_FACTOR = 1e38;

    /// @notice The address of the asset used by the USDN protocol
    IERC20Metadata internal immutable _asset;

    /// @notice The number of decimals of the asset used by the USDN protocol
    uint256 internal immutable _assetDecimals;

    /// @notice The address of the USDN protocol
    IUsdnProtocol internal immutable _usdnProtocol;

    /// @notice The current position version
    uint128 internal _positionVersion;

    /// @notice The amount of assets waiting to be used in the next version of the position
    uint128 internal _pendingAssetsAmount;

    /// @notice The maximum leverage that a position can have
    uint256 internal _maxLeverage;

    /// @notice The version of the last position that got liquidated
    uint128 internal _lastLiquidatedVersion;

    /// @notice The minimum amount of assets to be deposited by a user
    uint256 internal _minAssetDeposit;

    /// @notice The limit of the imbalance in bps to close the position
    uint256 internal _closeImbalanceLimitBps = 500;

    /// @notice The data about the assets deposited in this contract by users
    mapping(address => UserDeposit) internal _userDeposit;

    /// @notice The data for the specific version of the position
    mapping(uint256 => PositionData) internal _positionData;

    /// @param usdnProtocol The address of the USDN protocol
    constructor(IUsdnProtocol usdnProtocol) Ownable(msg.sender) {
        _usdnProtocol = usdnProtocol;
        IERC20Metadata asset = usdnProtocol.getAsset();
        _asset = asset;
        _assetDecimals = usdnProtocol.getAssetDecimals();
        _maxLeverage = usdnProtocol.getMaxLeverage();
        _minAssetDeposit = usdnProtocol.getMinLongPosition();

        // set allowance to allow the protocol to pull assets from this contract
        asset.forceApprove(address(usdnProtocol), type(uint256).max);

        // indicate that there are no position for version 0
        _positionData[0].id = PositionId({ tick: usdnProtocol.NO_POSITION_TICK(), tickVersion: 0, index: 0 });
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
    function getPendingAssetsAmount() external view returns (uint128) {
        return _pendingAssetsAmount;
    }

    /// @inheritdoc IRebalancer
    function getPositionVersion() external view returns (uint128) {
        return _positionVersion;
    }

    /// @inheritdoc IRebalancer
    function getPositionMaxLeverage() external view returns (uint256 maxLeverage_) {
        maxLeverage_ = _maxLeverage;
        uint256 protocolMaxLeverage = _usdnProtocol.getMaxLeverage();
        if (protocolMaxLeverage < maxLeverage_) {
            return protocolMaxLeverage;
        }
    }

    /// @inheritdoc IBaseRebalancer
    function getCurrentStateData()
        external
        view
        returns (uint128 pendingAssets_, uint256 maxLeverage_, PositionId memory currentPosId_)
    {
        return (_pendingAssetsAmount, _maxLeverage, _positionData[_positionVersion].id);
    }

    /// @inheritdoc IRebalancer
    function getLastLiquidatedVersion() external view returns (uint128) {
        return _lastLiquidatedVersion;
    }

    /// @inheritdoc IBaseRebalancer
    function getMinAssetDeposit() external view returns (uint256) {
        return _minAssetDeposit;
    }

    /// @inheritdoc IRebalancer
    function getPositionData(uint128 version) external view returns (PositionData memory positionData_) {
        positionData_ = _positionData[version];
    }

    /// @inheritdoc IRebalancer
    function getCloseImbalanceLimitBps() external view returns (uint256) {
        return _closeImbalanceLimitBps;
    }

    /// @inheritdoc IBaseRebalancer
    function getUserDepositData(address user) external view returns (UserDeposit memory) {
        return _userDeposit[user];
    }

    /// @inheritdoc IRebalancer
    function increaseAssetAllowance(uint256 addAllowance) external {
        _asset.safeIncreaseAllowance(address(_usdnProtocol), addAllowance);
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
            if (depositData.entryPositionVersion <= _lastLiquidatedVersion) {
                // if the user was in a position that got liquidated, we should reset its data
                delete depositData;
            } else if (depositData.entryPositionVersion <= positionVersion) {
                // if the user already deposited assets that are in a position, revert
                revert RebalancerUserNotPending();
            }
        }

        depositData.entryPositionVersion = positionVersion + 1;
        depositData.amount += amount;
        _userDeposit[to] = depositData;
        _pendingAssetsAmount += amount;

        _asset.safeTransferFrom(msg.sender, address(this), amount);

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

        if (depositData.amount == 0) {
            revert RebalancerUserNotPending();
        }

        if (depositData.entryPositionVersion <= _positionVersion) {
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

    /// @inheritdoc IBaseRebalancer
    function updatePosition(PositionId calldata newPosId, uint128 previousPosValue) external onlyProtocol {
        uint128 positionVersion = _positionVersion;
        PositionData memory previousPositionData = _positionData[positionVersion];
        // set the multiplier accumulator to 1 by default
        uint256 accMultiplier = MULTIPLIER_FACTOR;

        // if the current position version exists
        if (previousPositionData.amount > 0) {
            // if the position has not been liquidated
            if (previousPosValue > 0) {
                // update the multiplier accumulator
                accMultiplier = FixedPointMathLib.fullMulDiv(
                    previousPosValue, previousPositionData.entryAccMultiplier, previousPositionData.amount
                );
            } else {
                // update the last liquidated version tracker
                _lastLiquidatedVersion = positionVersion;
            }
        }

        // update the position's version
        ++positionVersion;
        _positionVersion = positionVersion;

        // save the data of the new position's version
        PositionData storage newPositionData = _positionData[positionVersion];
        newPositionData.entryAccMultiplier = accMultiplier;
        newPositionData.amount = _pendingAssetsAmount + previousPosValue;
        newPositionData.id = newPosId;

        // Reset the pending assets amount as they are all used in the new position
        _pendingAssetsAmount = 0;

        emit PositionVersionUpdated(positionVersion);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IOwnershipCallback).interfaceId) {
            return true;
        }
        if (interfaceId == type(IRebalancer).interfaceId) {
            return true;
        }
        if (interfaceId == type(IBaseRebalancer).interfaceId) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IRebalancer
    function setPositionMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        IUsdnProtocol protocol = _usdnProtocol;
        if (newMaxLeverage < protocol.getMinLeverage() || newMaxLeverage > protocol.getMaxLeverage()) {
            revert RebalancerInvalidMaxLeverage();
        }

        _maxLeverage = newMaxLeverage;

        emit PositionMaxLeverageUpdated(newMaxLeverage);
    }

    /// @inheritdoc IBaseRebalancer
    function setMinAssetDeposit(uint256 minAssetDeposit) external onlyAdmin {
        if (_usdnProtocol.getMinLongPosition() > minAssetDeposit) {
            revert RebalancerInvalidMinAssetDeposit();
        }

        _minAssetDeposit = minAssetDeposit;
        emit MinAssetDepositUpdated(minAssetDeposit);
    }

    /// @inheritdoc IRebalancer
    function setCloseImbalanceLimitBps(uint256 closeImbalanceLimitBps) external onlyOwner {
        _closeImbalanceLimitBps = closeImbalanceLimitBps;

        emit CloseImbalanceLimitBpsUpdated(closeImbalanceLimitBps);
    }

    /// @inheritdoc IRebalancer
    function initiateClosePosition(
        uint128 amount,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_) {
        UserDeposit memory userDepositData = _userDeposit[msg.sender];

        if (amount == 0) {
            revert RebalancerInvalidAmount();
        }

        if (amount > userDepositData.amount) {
            revert RebalancerInvalidAmount();
        }

        uint128 remainingAssets = userDepositData.amount - amount;
        if (remainingAssets > 0 && remainingAssets < _minAssetDeposit) {
            revert RebalancerInvalidAmount();
        }

        if (userDepositData.entryPositionVersion == 0) {
            revert RebalancerUserPending();
        }

        uint256 positionVersion = _positionVersion;

        if (userDepositData.entryPositionVersion > positionVersion) {
            revert RebalancerUserPending();
        }

        PositionData memory currentPositionData = _positionData[positionVersion];

        uint256 amountToClose = FixedPointMathLib.fullMulDiv(
            amount,
            currentPositionData.entryAccMultiplier,
            _positionData[userDepositData.entryPositionVersion].entryAccMultiplier
        );

        // slither-disable-next-line reentrancy-eth
        success_ = _usdnProtocol.initiateClosePosition{ value: msg.value }(
            currentPositionData.id, amountToClose.toUint128(), to, validator, currentPriceData, previousActionsData
        );

        if (success_) {
            if (remainingAssets == 0) {
                delete _userDeposit[msg.sender];
            } else {
                // TODO check remaining bonus in another PR
                _userDeposit[msg.sender].amount = remainingAssets;
            }

            currentPositionData.amount -= amountToClose.toUint128();

            if (currentPositionData.amount == 0) {
                currentPositionData.id =
                    PositionId({ tick: _usdnProtocol.NO_POSITION_TICK(), tickVersion: 0, index: 0 });
            }

            _positionData[positionVersion] = currentPositionData;

            emit ClosePositionInitiated(msg.sender, amount, amountToClose, remainingAssets);
        }
    }

    /// @inheritdoc IOwnershipCallback
    function ownershipCallback(address, PositionId calldata) external pure {
        revert RebalancerUnauthorized(); // first version of the rebalancer contract so we are always reverting
    }
}
