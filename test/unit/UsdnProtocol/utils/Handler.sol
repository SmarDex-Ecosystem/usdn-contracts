// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import {
    PendingAction,
    VaultPendingAction,
    LongPendingAction,
    ProtocolAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocol, Position } from "src/UsdnProtocol/UsdnProtocol.sol";
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
    using LibBitmap for LibBitmap.Bitmap;

    constructor(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    ) UsdnProtocol(usdn, sdex, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector) { }

    /// @dev Useful to completely disable funding, which is normally initialized with a positive bias value
    function resetEMA() external {
        _EMA = 0;
    }

    /// @dev Push a pending item to the front of the pending actions queue
    function queuePushFront(PendingAction memory action) external returns (uint128 rawIndex_) {
        rawIndex_ = _pendingActionsQueue.pushFront(action);
        _pendingActions[action.user] = uint256(rawIndex_) + 1;
    }

    function i_initiateClosePosition(
        address user,
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) external returns (uint256 securityDepositValue_) {
        return _initiateClosePosition(user, tick, tickVersion, index, amountToClose, currentPriceData);
    }

    function i_validateClosePosition(address user, bytes calldata priceData) external {
        _validateClosePosition(user, priceData);
    }

    function i_removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) external {
        return _removeAmountFromPosition(tick, index, pos, amountToRemove, totalExpoToRemove);
    }

    function i_positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (int256 value_)
    {
        return _positionValue(currentPrice, liqPriceWithoutPenalty, positionTotalExpo);
    }

    function i_calculatePositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
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
    ) external view returns (uint256, int256) {
        return _assetToTransfer(currentPrice, tick, expo, liqMultiplier, tempTransferred);
    }

    function i_tickValue(uint256 currentPrice, int24 tick, uint256 tickTotalExpo) external view returns (int256) {
        return _tickValue(currentPrice, tick, tickTotalExpo);
    }

    function i_getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
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

    function i_calcSdexToBurn(uint256 usdnAmount) external view returns (uint256 toBurn_) {
        return _calcSdexToBurn(usdnAmount);
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

    function i_checkImbalanceLimitDeposit(uint256 depositValue) external view {
        _checkImbalanceLimitDeposit(depositValue);
    }

    function i_checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) external view {
        _checkImbalanceLimitWithdrawal(withdrawalValue, totalExpo);
    }

    function i_checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) external view {
        _checkImbalanceLimitOpen(openTotalExpoValue, openCollatValue);
    }

    function i_checkImbalanceLimitClose(uint256 closeExpoValue, uint256 closeCollatValue) external view {
        _checkImbalanceLimitClose(closeExpoValue, closeCollatValue);
    }

    function i_getLeverage(uint128 price, uint128 liqPrice) external pure returns (uint128) {
        return _getLeverage(price, liqPrice);
    }

    function i_bitmapIndexToTick(uint256 index) external view returns (int24) {
        return _bitmapIndexToTick(index);
    }

    function i_tickToBitmapIndex(int24 tick) external view returns (uint256) {
        return _tickToBitmapIndex(tick);
    }

    function findLastSetInTickBitmap(int24 searchFrom) external view returns (uint256 index) {
        return _tickBitmap.findLastSet(_tickToBitmapIndex(searchFrom));
    }

    function i_updateEMA(uint128 secondsElapsed) external returns (int256) {
        return _updateEMA(secondsElapsed);
    }

    function i_usdnRebase(uint128 assetPrice, bool ignoreInterval) external returns (bool) {
        return _usdnRebase(assetPrice, ignoreInterval);
    }

    function i_calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        external
        pure
        returns (uint256)
    {
        return _calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
    }

    function i_calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        external
        pure
        returns (uint256)
    {
        return _calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
    }

    function i_addPendingAction(address user, PendingAction memory action) external {
        _addPendingAction(user, action);
    }

    function i_getPendingAction(address user) external view returns (PendingAction memory, uint128) {
        return _getPendingAction(user);
    }

    function i_executePendingAction(PreviousActionsData calldata data) external returns (bool, bool, uint256) {
        return _executePendingAction(data);
    }

    function i_executePendingActionOrRevert(PreviousActionsData calldata data) external {
        _executePendingActionOrRevert(data);
    }

    function i_refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore)
        external
        payable
    {
        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
    }

    function i_createInitialDeposit(uint128 amount, uint128 price) external {
        _createInitialDeposit(amount, price);
    }

    function i_createInitialPosition(
        uint128 amount,
        uint128 price,
        int24 tick,
        uint128 leverage,
        uint128 positionTotalExpo
    ) external {
        _createInitialPosition(amount, price, tick, leverage, positionTotalExpo);
    }
}
