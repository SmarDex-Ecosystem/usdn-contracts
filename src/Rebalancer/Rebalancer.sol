// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IRebalancer } from "src/interfaces/Rebalancer/IRebalancer.sol";
import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title Rebalancer
 * @notice The goal of this contract is to re-balance the USDN protocol when liquidations reduce the long trading expo
 * It will manage only one position with enough trading expo to re-balance the protocol after liquidations
 * and close/open again with new and existing funds when the imbalance reaches a certain threshold
 */
contract Rebalancer is Ownable, IRebalancer {
    using SafeCast for uint256;
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

    /// @inheritdoc IRebalancer
    uint256 public constant MULTIPLIER_DECIMALS = 21;

    // TODO Use this constant instead of the doing the multiplication everywhere
    uint256 public constant MULTIPLIER_FACTOR = 10 ** MULTIPLIER_DECIMALS;

    /// @inheritdoc IRebalancer
    int24 public constant NO_POSITION_TICK = type(int24).min;

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

    /// @notice The maximum leverage a position can have
    uint256 internal _maxLeverage;

    /// @notice The version of the last position that got liquidated
    uint128 internal _lastLiquidatedVersion;

    /// @notice The minimum amount of assets to be deposited by a user
    uint256 internal _minAssetDeposit;

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

        // Set allowance to allow the protocol to pull assets from this contract
        asset.forceApprove(address(usdnProtocol), type(uint256).max);

        // indicate that there are no position for version 0
        _positionData[0].id = PositionId({ tick: NO_POSITION_TICK, tickVersion: 0, index: 0 });
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

    // TODO name sucks, find a better one
    /// @inheritdoc IRebalancer
    function getRebalancerData()
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

    /// @inheritdoc IRebalancer
    function getMinAssetDeposit() external view returns (uint256) {
        return _minAssetDeposit;
    }

    function getPositionData(uint128 version) external view returns (PositionData memory positionData_) {
        // TODO revert if version > _positionVersion ?
        positionData_ = _positionData[version];
    }

    /// @inheritdoc IRebalancer
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

    /// @inheritdoc IRebalancer
    function updatePosition(PositionId calldata newPosId, uint128 previousPosValue) external onlyProtocol {
        uint128 positionVersion = _positionVersion;
        PositionData memory currentPositionData = _positionData[positionVersion];
        // set the multiplier accumulator to 1 by default
        uint256 accMultiplier = 10 ** MULTIPLIER_DECIMALS;

        // if the current position version exists
        if (currentPositionData.amount > 0) {
            // if the position has not been liquidated
            if (previousPosValue > 0) {
                // save the pnl multiplier of the position
                uint128 pnlMultiplier = _calcPnlMultiplier(currentPositionData.amount, previousPosValue);
                _positionData[positionVersion].pnlMultiplier = pnlMultiplier;

                // update the multiplier accumulator
                // TODO use amounts to avoid
                accMultiplier = FixedPointMathLib.fullMulDiv(
                    currentPositionData.entryAccMultiplier, pnlMultiplier, 10 ** MULTIPLIER_DECIMALS
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
        newPositionData.entryAccMultiplier = accMultiplier.toUint128();
        newPositionData.amount = _pendingAssetsAmount + previousPosValue;
        newPositionData.id = newPosId;

        // Reset the pending assets amount as they are all used in the new position
        _pendingAssetsAmount = 0;

        emit PositionVersionUpdated(positionVersion);
    }

    /**
     * TODO add tests
     * @notice Calculate the PnL multiplier of a position
     * @param openAmount The amount of assets used to open the position
     * @param value The value of the position right now
     */
    function _calcPnlMultiplier(uint128 openAmount, uint128 value) internal pure returns (uint128 pnlMultiplier_) {
        // prevent division by 0
        if (openAmount == 0) {
            return 0;
        }

        pnlMultiplier_ = FixedPointMathLib.fullMulDiv(value, 10 ** MULTIPLIER_DECIMALS, openAmount).toUint128();
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

    /// @inheritdoc IRebalancer
    function setMinAssetDeposit(uint256 minAssetDeposit) external onlyAdmin {
        if (_usdnProtocol.getMinLongPosition() > minAssetDeposit) {
            revert RebalancerInvalidMinAssetDeposit();
        }

        _minAssetDeposit = minAssetDeposit;
        emit MinAssetDepositUpdated(minAssetDeposit);
    }
}
