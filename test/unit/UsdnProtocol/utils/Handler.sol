// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as ActionsVault } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { IBaseOracleMiddleware } from "../../../../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "../../../../src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolFallback } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { DoubleEndedQueue } from "../../../../src/libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { SignedMath } from "../../../../src/libraries/SignedMath.sol";

/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolHandler is UsdnProtocolImpl, Test {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedMath for int256;

    Storage _tempStorage;

    function initializeStorageHandler(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Managers memory managers,
        IUsdnProtocolFallback protocolFallback
    ) public initializer {
        initializeStorage(
            usdn,
            sdex,
            asset,
            oracleMiddleware,
            liquidationRewardsManager,
            tickSpacing,
            feeCollector,
            managers,
            protocolFallback
        );
    }

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
    function mockLiquidate(bytes calldata currentPriceData, uint16 iterations)
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
        bytes32 tickHash = Core.tickHash(tick, s._tickVersion[tick]);
        return Long._tickValue(
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
        ApplyPnlAndFundingData memory data = Core._applyPnlAndFunding(s, currentPrice, uint128(block.timestamp));
        if (!data.isPriceRecent) {
            revert("price was not updated");
        }
        s._balanceLong = data.tempLongBalance.toUint256();
        s._balanceVault = data.tempVaultBalance.toUint256();
    }

    function removePendingAction(uint128 rawIndex, address user) external {
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    function i_createWithdrawalPendingAction(
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        ActionsVault.WithdrawalData memory data
    ) public returns (uint256 amountToRefund_) {
        return ActionsVault._createWithdrawalPendingAction(s, to, validator, usdnShares, securityDepositValue, data);
    }

    function i_createDepositPendingAction(
        address validator,
        address to,
        uint64 securityDepositValue,
        uint128 amount,
        ActionsVault.InitiateDepositData memory data
    ) external returns (uint256 amountToRefund_) {
        return ActionsVault._createDepositPendingAction(s, validator, to, securityDepositValue, amount, data);
    }

    function i_createOpenPendingAction(
        address to,
        address validator,
        uint64 securityDepositValue,
        InitiateOpenPositionData memory data
    ) public returns (uint256 amountToRefund_) {
        return ActionsUtils._createOpenPendingAction(s, to, validator, securityDepositValue, data);
    }

    function i_createClosePendingAction(
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        ClosePositionData memory data
    ) external returns (uint256 amountToRefund_) {
        return
            ActionsUtils._createClosePendingAction(s, to, validator, posId, amountToClose, securityDepositValue, data);
    }

    function findLastSetInTickBitmap(int24 searchFrom) external view returns (uint256 index) {
        return s._tickBitmap.findLastSet(Core._calcBitmapIndexFromTick(s, searchFrom));
    }

    function tickBitmapStatus(int24 tick) external view returns (bool isSet_) {
        return s._tickBitmap.get(Core._calcBitmapIndexFromTick(s, tick));
    }

    function setTickVersion(int24 tick, uint256 version) external {
        s._tickVersion[tick] = version;
    }

    function setPendingProtocolFee(uint256 value) external {
        s._pendingProtocolFee = value;
    }

    /**
     * @notice Helper to calculate the trading exposure of the long side at the time of the last balance update and
     * currentPrice
     */
    function getLongTradingExpo(uint128 currentPrice) external view returns (int256 expo_) {
        expo_ = s._totalExpo.toInt256().safeSub(Core._longAssetAvailable(s, currentPrice));
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
        return ActionsLong._initiateClosePosition(
            s, owner, to, validator, posId, amountToClose, securityDepositValue, currentPriceData
        );
    }

    function i_validateOpenPosition(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        return ActionsLong._validateOpenPosition(s, user, priceData);
    }

    function i_validateClosePosition(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        return ActionsLong._validateClosePosition(s, user, priceData);
    }

    function i_validateWithdrawal(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        return ActionsVault._validateWithdrawal(s, user, priceData);
    }

    function i_validateDeposit(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        return ActionsVault._validateDeposit(s, user, priceData);
    }

    function i_removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) external returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        liqMultiplierAccumulator_ =
            ActionsUtils._removeAmountFromPosition(s, tick, index, pos, amountToRemove, totalExpoToRemove);
    }

    function i_positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (int256 value_)
    {
        return Long._positionValue(currentPrice, liqPriceWithoutPenalty, positionTotalExpo);
    }

    function i_calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
    {
        return Long._calcPositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    function i_getActionablePendingAction() external returns (PendingAction memory, uint128) {
        return Core._getActionablePendingAction(s);
    }

    function i_lastFundingPerDay() external view returns (int256) {
        return s._lastFundingPerDay;
    }

    function i_applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        external
        returns (ApplyPnlAndFundingData memory data_)
    {
        return Core._applyPnlAndFunding(s, currentPrice, timestamp);
    }

    function i_liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) external returns (LiquidationsEffects memory effects_) {
        return Long._liquidatePositions(s, currentPrice, iteration, tempLongBalance, tempVaultBalance);
    }

    function i_toDepositPendingAction(PendingAction memory action)
        external
        pure
        returns (DepositPendingAction memory)
    {
        return Core._toDepositPendingAction(action);
    }

    function i_toWithdrawalPendingAction(PendingAction memory action)
        external
        pure
        returns (WithdrawalPendingAction memory)
    {
        return Core._toWithdrawalPendingAction(action);
    }

    function i_toLongPendingAction(PendingAction memory action) external pure returns (LongPendingAction memory) {
        return Core._toLongPendingAction(action);
    }

    function i_convertDepositPendingAction(DepositPendingAction memory action)
        external
        pure
        returns (PendingAction memory)
    {
        return Core._convertDepositPendingAction(action);
    }

    function i_convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        external
        pure
        returns (PendingAction memory)
    {
        return Core._convertWithdrawalPendingAction(action);
    }

    function i_convertLongPendingAction(LongPendingAction memory action) external pure returns (PendingAction memory) {
        return Core._convertLongPendingAction(action);
    }

    function i_assetToRemove(uint128 priceWithFees, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        external
        view
        returns (uint256)
    {
        return ActionsUtils._assetToRemove(s, priceWithFees, liqPriceWithoutPenalty, posExpo);
    }

    function i_tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) external view returns (int256) {
        return Long._tickValue(s, tick, currentPrice, longTradingExpo, accumulator, tickData);
    }

    function i_getOraclePrice(ProtocolAction action, uint256 timestamp, bytes32 actionId, bytes calldata priceData)
        external
        payable
        returns (PriceInfo memory)
    {
        return ActionsVault._getOraclePrice(s, action, timestamp, actionId, priceData);
    }

    function i_calcMintUsdnShares(uint256 amount, uint256 vaultBalance, uint256 usdnTotalShares, uint256 price)
        external
        view
        returns (uint256 toMint_)
    {
        return Vault._calcMintUsdnShares(s, amount, vaultBalance, usdnTotalShares, price);
    }

    function i_calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) external pure returns (uint256) {
        return Vault._calcSdexToBurn(usdnAmount, sdexBurnRatio);
    }

    function i_vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) external pure returns (int256 available_) {
        return Vault._vaultAssetAvailable(totalExpo, balanceVault, balanceLong, newPrice, oldPrice);
    }

    function i_vaultAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return Vault._vaultAssetAvailable(s, currentPrice);
    }

    function i_tickHash(int24 tick) external view returns (bytes32, uint256) {
        return Core._tickHash(s, tick);
    }

    function i_longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        external
        pure
        returns (int256 available_)
    {
        return Core._longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);
    }

    function i_longAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return Core._longAssetAvailable(s, currentPrice);
    }

    function i_getLiquidationPrice(uint128 startPrice, uint128 leverage) external pure returns (uint128) {
        return Long._getLiquidationPrice(startPrice, leverage);
    }

    function i_checkImbalanceLimitDeposit(uint256 depositValue) external view {
        ActionsVault._checkImbalanceLimitDeposit(s, depositValue);
    }

    function i_checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) external view {
        ActionsVault._checkImbalanceLimitWithdrawal(s, withdrawalValue, totalExpo);
    }

    function i_checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) external view {
        Long._checkImbalanceLimitOpen(s, openTotalExpoValue, openCollatValue);
    }

    function i_checkImbalanceLimitClose(uint256 posTotalExpoToClose, uint256 posValueToClose) external view {
        ActionsUtils._checkImbalanceLimitClose(s, posTotalExpoToClose, posValueToClose);
    }

    function i_getLeverage(uint128 price, uint128 liqPrice) external pure returns (uint256) {
        return Long._getLeverage(price, liqPrice);
    }

    function i_calcTickFromBitmapIndex(uint256 index) external view returns (int24) {
        return Long._calcTickFromBitmapIndex(s, index);
    }

    function i_calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) external pure returns (int24) {
        return Long._calcTickFromBitmapIndex(index, tickSpacing);
    }

    function i_calcBitmapIndexFromTick(int24 tick) external view returns (uint256) {
        return Core._calcBitmapIndexFromTick(s, tick);
    }

    function i_calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) external pure returns (uint256) {
        return Core._calcBitmapIndexFromTick(tick, tickSpacing);
    }

    function i_calcLiqPriceFromTradingExpo(uint128 currentPrice, uint128 amount, uint256 tradingExpo)
        external
        pure
        returns (uint128 liqPrice_)
    {
        return Long._calcLiqPriceFromTradingExpo(currentPrice, amount, tradingExpo);
    }

    function i_findHighestPopulatedTick(int24 searchStart) external view returns (int24 tick_) {
        return Long._findHighestPopulatedTick(s, searchStart);
    }

    function i_updateEMA(int256 fundingPerDay, uint128 secondsElapsed) external {
        Core._updateEMA(s, fundingPerDay, secondsElapsed);
    }

    function i_usdnRebase(uint128 assetPrice, bool ignoreInterval) external returns (bool, bytes memory) {
        return Vault._usdnRebase(s, assetPrice, ignoreInterval);
    }

    function i_calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        external
        pure
        returns (uint256)
    {
        return Vault._calcUsdnPrice(vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
    }

    function i_calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        external
        pure
        returns (uint256)
    {
        return Vault._calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
    }

    function i_addPendingAction(address user, PendingAction memory action) external returns (uint256) {
        return Core._addPendingAction(s, user, action);
    }

    function i_getPendingAction(address user) external view returns (PendingAction memory, uint128) {
        return Core._getPendingAction(s, user);
    }

    function i_getPendingActionOrRevert(address user) external view returns (PendingAction memory, uint128) {
        return Core._getPendingActionOrRevert(s, user);
    }

    function i_executePendingAction(PreviousActionsData calldata data) external returns (bool, bool, bool, uint256) {
        return ActionsVault._executePendingAction(s, data);
    }

    function i_executePendingActionOrRevert(PreviousActionsData calldata data) external {
        ActionsVault._executePendingActionOrRevert(s, data);
    }

    function i_refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore)
        external
        payable
    {
        ActionsVault._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
    }

    function i_refundEther(uint256 amount, address payable to) external payable {
        ActionsVault._refundEther(amount, to);
    }

    function i_mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB) external pure returns (uint256) {
        return Core._mergeWithdrawalAmountParts(sharesLSB, sharesMSB);
    }

    function i_calcWithdrawalAmountLSB(uint152 usdnShares) external pure returns (uint24) {
        return Vault._calcWithdrawalAmountLSB(usdnShares);
    }

    function i_calcWithdrawalAmountMSB(uint152 usdnShares) external pure returns (uint128) {
        return Vault._calcWithdrawalAmountMSB(usdnShares);
    }

    function i_createInitialDeposit(uint128 amount, uint128 price) external {
        Vault._createInitialDeposit(s, amount, price);
    }

    function i_createInitialPosition(uint128 amount, uint128 price, int24 tick, uint128 positionTotalExpo) external {
        Vault._createInitialPosition(s, amount, price, tick, positionTotalExpo);
    }

    function i_saveNewPosition(int24 tick, Position memory long, uint8 liquidationPenalty)
        external
        returns (uint256, uint256, HugeUint.Uint512 memory)
    {
        return ActionsUtils._saveNewPosition(s, tick, long, liquidationPenalty);
    }

    function i_checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) external view {
        Long._checkSafetyMargin(s, currentPrice, liquidationPrice);
    }

    function i_getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) external pure returns (uint128) {
        return Long._getEffectivePriceForTick(tick, liqMultiplier);
    }

    function i_calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint256) {
        return Long._calcFixedPrecisionMultiplier(assetPrice, longTradingExpo, accumulator);
    }

    function i_calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        external
        pure
        returns (uint256 assetExpected_)
    {
        return Vault._calcBurnUsdn(usdnShares, available, usdnTotalShares);
    }

    function i_calcTickWithoutPenalty(int24 tick, uint8 liquidationPenalty) external view returns (int24) {
        return Long._calcTickWithoutPenalty(s, tick, liquidationPenalty);
    }

    function i_calcTickWithoutPenalty(int24 tick) external view returns (int24) {
        return Long._calcTickWithoutPenalty(s, tick, s._liquidationPenalty);
    }

    function i_unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint256) {
        return Long._unadjustPrice(price, assetPrice, longTradingExpo, accumulator);
    }

    function i_clearPendingAction(address user, uint128 rawIndex) external {
        Core._clearPendingAction(s, user, rawIndex);
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

        return Long._calcRebalancerPositionTick(s, neutralPrice, positionAmount, rebalancerMaxLeverage, cache);
    }

    function i_calcImbalanceCloseBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_)
    {
        return Long._calcImbalanceCloseBps(vaultBalance, longBalance, longTotalExpo);
    }

    function i_calcImbalanceOpenBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_)
    {
        return Long._calcImbalanceOpenBps(vaultBalance, longBalance, longTotalExpo);
    }

    function i_removeBlockedPendingAction(uint128 rawIndex, address payable to, bool cleanup) external {
        Core._removeBlockedPendingAction(s, rawIndex, to, cleanup);
    }

    function i_checkInitImbalance(uint128 positionTotalExpo, uint128 longAmount, uint128 depositAmount) external view {
        Vault._checkInitImbalance(s, positionTotalExpo, longAmount, depositAmount);
    }

    function i_removeStalePendingAction(address user) external returns (uint256) {
        return Core._removeStalePendingAction(s, user);
    }

    function i_triggerRebalancer(
        uint128 lastPrice,
        uint256 longBalance,
        uint256 vaultBalance,
        int256 remainingCollateral
    ) public returns (uint256 longBalance_, uint256 vaultBalance_) {
        return Long._triggerRebalancer(s, lastPrice, longBalance, vaultBalance, remainingCollateral);
    }

    function i_calculateFee(int256 fundAsset) external returns (int256 fee_, int256 fundAssetWithFee_) {
        return Core._calculateFee(s, fundAsset);
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

        return Long._flashClosePosition(s, posId, neutralPrice, cache);
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

        return Long._flashOpenPosition(s, user, neutralPrice, tickWithoutPenalty, amount, cache);
    }

    function i_checkPendingFee() external {
        ActionsVault._checkPendingFee(s);
    }

    function i_sendRewardsToLiquidator(
        uint16 liquidatedTicks,
        int256 remainingCollateral,
        bool rebased,
        bool rebalancerTriggered,
        ProtocolAction action,
        bytes memory rebaseCallbackResult,
        bytes memory priceData
    ) external {
        ActionsUtils._sendRewardsToLiquidator(
            s,
            liquidatedTicks,
            remainingCollateral,
            rebased,
            rebalancerTriggered,
            action,
            rebaseCallbackResult,
            priceData
        );
    }

    function i_prepareInitiateDepositData(address validator, uint128 amount, bytes calldata currentPriceData)
        public
        returns (ActionsVault.InitiateDepositData memory data_)
    {
        return ActionsVault._prepareInitiateDepositData(s, validator, amount, currentPriceData);
    }

    function i_prepareWithdrawalData(address validator, uint152 usdnShares, bytes calldata currentPriceData)
        public
        returns (ActionsVault.WithdrawalData memory data_)
    {
        return ActionsVault._prepareWithdrawalData(s, validator, usdnShares, currentPriceData);
    }

    function i_prepareClosePositionData(
        address owner,
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) external returns (ClosePositionData memory data_, bool liquidated_) {
        return ActionsUtils._prepareClosePositionData(s, owner, to, validator, posId, amountToClose, currentPriceData);
    }

    function i_prepareValidateOpenPositionData(PendingAction memory pending, bytes calldata priceData)
        external
        returns (ValidateOpenPositionData memory data_, bool liquidated_)
    {
        return ActionsUtils._prepareValidateOpenPositionData(s, pending, priceData);
    }

    function i_checkInitiateClosePosition(
        address owner,
        address to,
        address validator,
        uint128 amountToClose,
        Position memory pos
    ) external view {
        ActionsUtils._checkInitiateClosePosition(s, owner, to, validator, amountToClose, pos);
    }

    /**
     * @notice These are the storage fields that are used by the `_funding` function
     * @dev We can pass these to `i_funding` to effectively make the function "pure", by controlling all variables
     * manually
     */
    struct FundingStorage {
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint128 lastUpdateTimestamp;
        uint256 fundingSF;
    }

    /**
     * @dev The first argument contains all the storage variables accessed by `_funding`, so that they can be
     * controlled manually in the tests
     */
    function i_funding(FundingStorage memory fundingStorage, uint128 timestamp, int256 ema)
        external
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_)
    {
        _tempStorage._totalExpo = fundingStorage.totalExpo;
        _tempStorage._balanceVault = fundingStorage.balanceVault;
        _tempStorage._balanceLong = fundingStorage.balanceLong;
        _tempStorage._lastUpdateTimestamp = fundingStorage.lastUpdateTimestamp;
        _tempStorage._fundingSF = fundingStorage.fundingSF;
        return Core._funding(_tempStorage, timestamp, ema);
    }
}
