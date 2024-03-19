// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {
    PendingAction,
    VaultPendingAction,
    LongPendingAction,
    ProtocolAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolHandler is UsdnProtocol {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    constructor(
        IUsdn usdn,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    ) UsdnProtocol(usdn, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector) { }

    /// @dev Useful to completely disable funding, which is normally initialized with a positive bias value
    function resetEMA() external {
        _EMA = 0;
    }

    /// @dev Push a pending item to the front of the pending actions queue
    function queuePushFront(PendingAction memory action) external returns (uint128 rawIndex_) {
        rawIndex_ = _pendingActionsQueue.pushFront(action);
        _pendingActions[action.user] = uint256(rawIndex_) + 1;
    }

    function i_validateClosePosition(address user, bytes calldata priceData) external {
        _validateClosePosition(user, priceData);
    }

    function i_positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (uint256 value_)
    {
        return _positionValue(currentPrice, liqPriceWithoutPenalty, positionTotalExpo);
    }

    function i_calculatePositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint256 totalExpo_)
    {
        return _calculatePositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    function i_removePendingAction(uint128 rawIndex, address user) external {
        _pendingActionsQueue.clearAt(rawIndex);
        delete _pendingActions[user];
    }

    function i_getActionablePendingAction() external returns (PendingAction memory, uint128) {
        return _getActionablePendingAction();
    }

    function i_vaultTradingExpo(uint128 currentPrice) external view returns (int256) {
        return _vaultTradingExpo(currentPrice);
    }

    function i_longTradingExpo(uint128 currentPrice) external view returns (int256) {
        return _longTradingExpo(currentPrice);
    }

    function i_lastFunding() external view returns (int256) {
        return _lastFunding;
    }

    function i_applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        external
        returns (bool priceUpdated_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        return _applyPnlAndFunding(currentPrice, timestamp);
    }

    function i_liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    )
        external
        returns (
            uint256 liquidatedPositions_,
            uint16 liquidatedTicks_,
            int256 remainingCollateral_,
            uint256 newLongBalance_,
            uint256 newVaultBalance_
        )
    {
        return _liquidatePositions(currentPrice, iteration, tempLongBalance, tempVaultBalance);
    }

    function i_toVaultPendingAction(PendingAction memory action) external pure returns (VaultPendingAction memory) {
        return _toVaultPendingAction(action);
    }

    function i_toLongPendingAction(PendingAction memory action) external pure returns (LongPendingAction memory) {
        return _toLongPendingAction(action);
    }

    function i_convertVaultPendingAction(VaultPendingAction memory action)
        external
        pure
        returns (PendingAction memory)
    {
        return _convertVaultPendingAction(action);
    }

    function i_convertLongPendingAction(LongPendingAction memory action) external pure returns (PendingAction memory) {
        return _convertLongPendingAction(action);
    }

    function i_assetToTransfer(
        uint128 currentPrice,
        int24 tick,
        uint128 expo,
        uint256 liqMultiplier,
        uint256 tempTransferred
    ) external view returns (uint256) {
        return _assetToTransfer(currentPrice, tick, expo, liqMultiplier, tempTransferred);
    }

    function i_tickValue(uint256 currentPrice, int24 tick, uint256 tickTotalExpo) external view returns (int256) {
        return _tickValue(currentPrice, tick, tickTotalExpo);
    }

    function i_getOraclePrice(ProtocolAction action, uint40 timestamp, bytes calldata priceData)
        external
        payable
        returns (PriceInfo memory)
    {
        return _getOraclePrice(action, timestamp, priceData);
    }

    function i_calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        external
        view
        returns (uint256 toMint_)
    {
        return _calcMintUsdn(amount, vaultBalance, usdnTotalSupply, price);
    }

    function i_vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) external pure returns (int256 available_) {
        return _vaultAssetAvailable(totalExpo, balanceVault, balanceLong, newPrice, oldPrice);
    }

    function i_vaultAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return _vaultAssetAvailable(currentPrice);
    }

    function i_tickHash(int24 tick) external view returns (bytes32, uint256) {
        return _tickHash(tick);
    }

    function i_longAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return _longAssetAvailable(currentPrice);
    }

    function i_getLiquidationPrice(uint128 startPrice, uint128 leverage) external pure returns (uint128) {
        return _getLiquidationPrice(startPrice, leverage);
    }

    function i_getLeverage(uint128 price, uint128 liqPrice) external pure returns (uint128) {
        return _getLeverage(price, liqPrice);
    }

    function i_updateEMA(uint128 secondsElapsed) external returns (int256) {
        return _updateEMA(secondsElapsed);
    }

    function i_usdnRebase(uint128 assetPrice, bool ignoreInterval) external returns (bool) {
        return _usdnRebase(assetPrice, ignoreInterval);
    }

    function i_calcUsdnPrice(
        uint256 vaultBalance,
        uint128 assetPrice,
        uint256 usdnTotalSupply,
        uint8 usdnDecimals,
        uint8 assetDecimals
    ) external pure returns (uint256) {
        return _calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, usdnDecimals, assetDecimals);
    }

    function i_calcRebaseTotalSupply(
        uint256 vaultBalance,
        uint128 assetPrice,
        uint128 targetPrice,
        uint8 usdnDecimals,
        uint8 assetDecimals
    ) external pure returns (uint256) {
        return _calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, usdnDecimals, assetDecimals);
    }

    function i_addPendingAction(address user, PendingAction memory action) external {
        _addPendingAction(user, action);
    }

    function i_getPendingAction(address user) external view returns (PendingAction memory, uint128) {
        return _getPendingAction(user);
    }

    function i_executePendingAction(PreviousActionsData calldata data) external returns (bool, bool) {
        return _executePendingAction(data);
    }

    function i_executePendingActionOrRevert(PreviousActionsData calldata data) external {
        _executePendingActionOrRevert(data);
    }
}
