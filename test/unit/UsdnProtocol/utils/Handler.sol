// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    ProtocolAction,
    PreviousActionsData,
    TickData,
    PositionId,
    CachedProtocolState
} from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocol } from "../../../../src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "../../../../src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../../../../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { DoubleEndedQueue } from "../../../../src/libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { Position, LiquidationsEffects } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "../../../../src/libraries/SignedMath.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as longLib } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as actionsVaultLib } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolActionsLongLibrary as actionsLongLib } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as actionsUtilsLib } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsUtilsLibrary.sol";

/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolHandler is UsdnProtocol, Test {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedMath for int256;

    constructor(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    ) UsdnProtocol(usdn, sdex, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector) { }

    /// @dev Useful to completely disable funding, which is normally initialized with a positive bias value
    function resetEMA() external {
        s._EMA = 0;
    }

    /// @dev Push a pending item to the front of the pending actions queue
    function queuePushFront(PendingAction memory action) external returns (uint128 rawIndex_) {
        rawIndex_ = s._pendingActionsQueue.pushFront(action);
        s._pendingActions[action.validator] = uint256(rawIndex_) + 1;
    }

    /// @dev Verify if the pending actions queue is empty
    function queueEmpty() external view returns (bool) {
        return s._pendingActionsQueue.empty();
    }

    function getQueueItem(uint128 rawIndex) external view returns (PendingAction memory) {
        return s._pendingActionsQueue.atRaw(rawIndex);
    }

    /**
     * @dev Use this function in unit tests to make sure we provide a fresh price that updates the balances
     * The function reverts the price given by the mock oracle middleware is not fresh enough to trigger a balance
     * update. Call `_waitBeforeLiquidation()` before calling this function to make sure enough time has passed.
     * Do not use this function in contexts where ether needs to be refunded.
     */
    function testLiquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidatedPositions_)
    {
        uint256 lastUpdateTimestampBefore = s._lastUpdateTimestamp;
        vm.startPrank(msg.sender);
        liquidatedPositions_ = this.liquidate(currentPriceData, iterations);
        vm.stopPrank();
        require(s._lastUpdateTimestamp > lastUpdateTimestampBefore, "UsdnProtocolHandler: liq price is not fresh");
    }

    function tickValue(int24 tick, uint256 currentPrice) external view returns (int256) {
        int256 longTradingExpo = this.longTradingExpoWithFunding(uint128(currentPrice), uint128(block.timestamp));
        if (longTradingExpo < 0) {
            longTradingExpo = 0;
        }
        bytes32 tickHash = actionsLongLib.tickHash(tick, s._tickVersion[tick]);
        return longLib._tickValue(
            s, tick, currentPrice, uint256(longTradingExpo), s._liqMultiplierAccumulator, s._tickData[tickHash]
        );
    }

    /**
     * @dev Helper function to simulate a situation where the vault would be empty. In practice, it's not possible to
     * achieve.
     */
    function emptyVault() external {
        s._balanceLong += s._balanceVault;
        s._balanceVault = 0;
    }

    function updateBalances(uint128 currentPrice) external {
        (bool priceUpdated, int256 tempLongBalance, int256 tempVaultBalance) =
            coreLib._applyPnlAndFunding(s, currentPrice, uint128(block.timestamp));
        if (!priceUpdated) {
            revert("price was not updated");
        }
        s._balanceLong = tempLongBalance.toUint256();
        s._balanceVault = tempVaultBalance.toUint256();
    }

    function removePendingAction(uint128 rawIndex, address user) external {
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    function findLastSetInTickBitmap(int24 searchFrom) external view returns (uint256 index) {
        return s._tickBitmap.findLastSet(coreLib._calcBitmapIndexFromTick(s, searchFrom));
    }

    function tickBitmapStatus(int24 tick) external view returns (bool isSet_) {
        return s._tickBitmap.get(coreLib._calcBitmapIndexFromTick(s, tick));
    }

    function setTickVersion(int24 tick, uint256 version) external {
        s._tickVersion[tick] = version;
    }

    function i_initiateClosePosition(
        address owner,
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) external returns (uint256 securityDepositValue_, bool isLiquidationPending_, bool liq_) {
        return actionsLongLib._initiateClosePosition(
            s, owner, to, validator, posId, amountToClose, securityDepositValue, currentPriceData
        );
    }

    function i_validateClosePosition(address user, bytes calldata priceData) external {
        actionsLongLib._validateClosePosition(s, user, priceData);
    }

    function i_removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) external returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        liqMultiplierAccumulator_ =
            actionsUtilsLib._removeAmountFromPosition(s, tick, index, pos, amountToRemove, totalExpoToRemove);
    }

    function i_positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (int256 value_)
    {
        return longLib._positionValue(currentPrice, liqPriceWithoutPenalty, positionTotalExpo);
    }

    function i_calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
    {
        return longLib._calcPositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    function i_getActionablePendingAction() external returns (PendingAction memory, uint128) {
        return coreLib._getActionablePendingAction(s);
    }

    function i_lastFunding() external view returns (int256) {
        return s._lastFunding;
    }

    function i_applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        external
        returns (bool priceUpdated_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        return coreLib._applyPnlAndFunding(s, currentPrice, timestamp);
    }

    function i_liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) external returns (LiquidationsEffects memory effects_) {
        return longLib._liquidatePositions(s, currentPrice, iteration, tempLongBalance, tempVaultBalance);
    }

    function i_toDepositPendingAction(PendingAction memory action)
        external
        pure
        returns (DepositPendingAction memory)
    {
        return coreLib._toDepositPendingAction(action);
    }

    function i_toWithdrawalPendingAction(PendingAction memory action)
        external
        pure
        returns (WithdrawalPendingAction memory)
    {
        return coreLib._toWithdrawalPendingAction(action);
    }

    function i_toLongPendingAction(PendingAction memory action) external pure returns (LongPendingAction memory) {
        return coreLib._toLongPendingAction(action);
    }

    function i_convertDepositPendingAction(DepositPendingAction memory action)
        external
        pure
        returns (PendingAction memory)
    {
        return coreLib._convertDepositPendingAction(action);
    }

    function i_convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        external
        pure
        returns (PendingAction memory)
    {
        return coreLib._convertWithdrawalPendingAction(action);
    }

    function i_convertLongPendingAction(LongPendingAction memory action) external pure returns (PendingAction memory) {
        return coreLib._convertLongPendingAction(action);
    }

    function i_assetToRemove(uint128 priceWithFees, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        external
        view
        returns (uint256)
    {
        return actionsUtilsLib._assetToRemove(s, priceWithFees, liqPriceWithoutPenalty, posExpo);
    }

    function i_tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) external view returns (int256) {
        return longLib._tickValue(s, tick, currentPrice, longTradingExpo, accumulator, tickData);
    }

    function i_getOraclePrice(ProtocolAction action, uint256 timestamp, bytes32 actionId, bytes calldata priceData)
        external
        payable
        returns (PriceInfo memory)
    {
        return actionsVaultLib._getOraclePrice(s, action, timestamp, actionId, priceData);
    }

    function i_calcMintUsdnShares(uint256 amount, uint256 vaultBalance, uint256 usdnTotalShares, uint256 price)
        external
        view
        returns (uint256 toMint_)
    {
        return vaultLib._calcMintUsdnShares(s, amount, vaultBalance, usdnTotalShares, price);
    }

    function i_calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) external pure returns (uint256) {
        return vaultLib._calcSdexToBurn(usdnAmount, sdexBurnRatio);
    }

    function i_vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) external pure returns (int256 available_) {
        return vaultLib._vaultAssetAvailable(totalExpo, balanceVault, balanceLong, newPrice, oldPrice);
    }

    function i_vaultAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return vaultLib._vaultAssetAvailable(s, currentPrice);
    }

    function i_tickHash(int24 tick) external view returns (bytes32, uint256) {
        return vaultLib._tickHash(s, tick);
    }

    function i_longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        external
        pure
        returns (int256 available_)
    {
        return coreLib._longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);
    }

    function i_longAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return coreLib._longAssetAvailable(s, currentPrice);
    }

    function i_getLiquidationPrice(uint128 startPrice, uint128 leverage) external pure returns (uint128) {
        return longLib._getLiquidationPrice(startPrice, leverage);
    }

    function i_checkImbalanceLimitDeposit(uint256 depositValue) external view {
        actionsVaultLib._checkImbalanceLimitDeposit(s, depositValue);
    }

    function i_checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) external view {
        actionsVaultLib._checkImbalanceLimitWithdrawal(s, withdrawalValue, totalExpo);
    }

    function i_checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) external view {
        longLib._checkImbalanceLimitOpen(s, openTotalExpoValue, openCollatValue);
    }

    function i_checkImbalanceLimitClose(uint256 posTotalExpoToClose, uint256 posValueToClose) external view {
        actionsUtilsLib._checkImbalanceLimitClose(s, posTotalExpoToClose, posValueToClose);
    }

    function i_getLeverage(uint128 price, uint128 liqPrice) external pure returns (uint128) {
        return longLib._getLeverage(price, liqPrice);
    }

    function i_calcTickFromBitmapIndex(uint256 index) external view returns (int24) {
        return longLib._calcTickFromBitmapIndex(s, index);
    }

    function i_calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) external pure returns (int24) {
        return longLib._calcTickFromBitmapIndex(index, tickSpacing);
    }

    function i_calcBitmapIndexFromTick(int24 tick) external view returns (uint256) {
        return coreLib._calcBitmapIndexFromTick(s, tick);
    }

    function i_calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) external pure returns (uint256) {
        return coreLib._calcBitmapIndexFromTick(tick, tickSpacing);
    }

    function i_calcLiqPriceFromTradingExpo(uint128 currentPrice, uint128 amount, uint256 tradingExpo)
        external
        pure
        returns (uint128 liqPrice_)
    {
        return longLib._calcLiqPriceFromTradingExpo(currentPrice, amount, tradingExpo);
    }

    function i_findHighestPopulatedTick(int24 searchStart) external view returns (int24 tick_) {
        return longLib._findHighestPopulatedTick(s, searchStart);
    }

    function i_updateEMA(uint128 secondsElapsed) external returns (int256) {
        return coreLib._updateEMA(s, secondsElapsed);
    }

    function i_usdnRebase(uint128 assetPrice, bool ignoreInterval) external returns (bool, bytes memory) {
        return vaultLib._usdnRebase(s, assetPrice, ignoreInterval);
    }

    function i_calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        external
        pure
        returns (uint256)
    {
        return vaultLib._calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
    }

    function i_calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        external
        pure
        returns (uint256)
    {
        return vaultLib._calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
    }

    function i_addPendingAction(address user, PendingAction memory action) external returns (uint256) {
        return coreLib._addPendingAction(s, user, action);
    }

    function i_getPendingAction(address user) external view returns (PendingAction memory, uint128) {
        return coreLib._getPendingAction(s, user);
    }

    function i_getPendingActionOrRevert(address user) external view returns (PendingAction memory, uint128) {
        return coreLib._getPendingActionOrRevert(s, user);
    }

    function i_executePendingAction(PreviousActionsData calldata data) external returns (bool, bool, bool, uint256) {
        return actionsVaultLib._executePendingAction(s, data);
    }

    function i_executePendingActionOrRevert(PreviousActionsData calldata data) external {
        actionsVaultLib._executePendingActionOrRevert(s, data);
    }

    function i_refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore)
        external
        payable
    {
        actionsVaultLib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
    }

    function i_refundEther(uint256 amount, address payable to) external payable {
        actionsVaultLib._refundEther(amount, to);
    }

    function i_mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB) external pure returns (uint256) {
        return coreLib._mergeWithdrawalAmountParts(sharesLSB, sharesMSB);
    }

    function i_calcWithdrawalAmountLSB(uint152 usdnShares) external pure returns (uint24) {
        return vaultLib._calcWithdrawalAmountLSB(usdnShares);
    }

    function i_calcWithdrawalAmountMSB(uint152 usdnShares) external pure returns (uint128) {
        return vaultLib._calcWithdrawalAmountMSB(usdnShares);
    }

    function i_createInitialDeposit(uint128 amount, uint128 price) external {
        vaultLib._createInitialDeposit(s, amount, price);
    }

    function i_createInitialPosition(uint128 amount, uint128 price, int24 tick, uint128 positionTotalExpo) external {
        vaultLib._createInitialPosition(s, amount, price, tick, positionTotalExpo);
    }

    function i_saveNewPosition(int24 tick, Position memory long, uint8 liquidationPenalty)
        external
        returns (uint256, uint256, HugeUint.Uint512 memory)
    {
        return actionsUtilsLib._saveNewPosition(s, tick, long, liquidationPenalty);
    }

    function i_checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) external view {
        longLib._checkSafetyMargin(s, currentPrice, liquidationPrice);
    }

    function i_getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) external pure returns (uint128) {
        return longLib._getEffectivePriceForTick(tick, liqMultiplier);
    }

    function i_calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint256) {
        return longLib._calcFixedPrecisionMultiplier(assetPrice, longTradingExpo, accumulator);
    }

    function i_calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        external
        pure
        returns (uint256 assetExpected_)
    {
        return vaultLib._calcBurnUsdn(usdnShares, available, usdnTotalShares);
    }

    function i_calcTickWithoutPenalty(int24 tick, uint8 liquidationPenalty) external view returns (int24) {
        return longLib._calcTickWithoutPenalty(s, tick, liquidationPenalty);
    }

    function i_calcTickWithoutPenalty(int24 tick) external view returns (int24) {
        return longLib._calcTickWithoutPenalty(s, tick, s._liquidationPenalty);
    }

    function i_unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint256) {
        return longLib._unadjustPrice(price, assetPrice, longTradingExpo, accumulator);
    }

    function i_clearPendingAction(address user, uint128 rawIndex) external {
        coreLib._clearPendingAction(s, user, rawIndex);
    }

    function i_calcRebalancerPositionTick(
        uint128 neutralPrice,
        uint128 positionAmount,
        uint256 rebalancerMaxLeverage,
        uint256 totalExpo,
        uint256 balanceLong,
        uint256 balanceVault,
        HugeUint.Uint512 memory liqMultiplierAccumulator
    ) external view returns (int24 tickWithoutLiqPenalty_) {
        CachedProtocolState memory cache = CachedProtocolState({
            totalExpo: totalExpo,
            longBalance: balanceLong,
            vaultBalance: balanceVault,
            tradingExpo: totalExpo - balanceLong,
            liqMultiplierAccumulator: liqMultiplierAccumulator
        });

        return longLib._calcRebalancerPositionTick(s, neutralPrice, positionAmount, rebalancerMaxLeverage, cache);
    }

    function i_calcImbalanceCloseBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_)
    {
        return longLib._calcImbalanceCloseBps(vaultBalance, longBalance, longTotalExpo);
    }

    function i_calcImbalanceOpenBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_)
    {
        return longLib._calcImbalanceOpenBps(vaultBalance, longBalance, longTotalExpo);
    }

    function i_removeBlockedPendingAction(uint128 rawIndex, address payable to, bool cleanup) external {
        coreLib._removeBlockedPendingAction(s, rawIndex, to, cleanup);
    }

    function i_checkInitImbalance(uint128 positionTotalExpo, uint128 longAmount, uint128 depositAmount) external view {
        vaultLib._checkInitImbalance(s, positionTotalExpo, longAmount, depositAmount);
    }

    function i_removeStalePendingAction(address user) external returns (uint256) {
        return coreLib._removeStalePendingAction(s, user);
    }

    function i_flashClosePosition(
        PositionId memory posId,
        uint128 neutralPrice,
        uint256 totalExpo,
        uint256 balanceLong,
        uint256 balanceVault,
        HugeUint.Uint512 memory liqMultiplierAccumulator
    ) external returns (int256 positionValue_) {
        CachedProtocolState memory cache = CachedProtocolState({
            totalExpo: totalExpo,
            longBalance: balanceLong,
            vaultBalance: balanceVault,
            tradingExpo: totalExpo - balanceLong,
            liqMultiplierAccumulator: liqMultiplierAccumulator
        });

        return longLib._flashClosePosition(s, posId, neutralPrice, cache);
    }

    function i_flashOpenPosition(
        address user,
        uint128 neutralPrice,
        int24 tickWithoutPenalty,
        uint128 amount,
        uint256 totalExpo,
        uint256 balanceLong,
        uint256 balanceVault,
        HugeUint.Uint512 memory liqMultiplierAccumulator
    ) external returns (PositionId memory posId_) {
        CachedProtocolState memory cache = CachedProtocolState({
            totalExpo: totalExpo,
            longBalance: balanceLong,
            vaultBalance: balanceVault,
            tradingExpo: totalExpo - balanceLong,
            liqMultiplierAccumulator: liqMultiplierAccumulator
        });

        return longLib._flashOpenPosition(s, user, neutralPrice, tickWithoutPenalty, amount, cache);
    }

    /**
     * @notice Helper to calculate the trading exposure of the long side at the time of the last balance update and
     * currentPrice
     */
    function getLongTradingExpo(uint128 currentPrice) external view returns (int256 expo_) {
        expo_ = s._totalExpo.toInt256().safeSub(coreLib._longAssetAvailable(s, currentPrice));
    }
}
