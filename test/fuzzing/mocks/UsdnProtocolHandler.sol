// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../../src/UsdnProtocol//libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolImpl } from "../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "../../../src/UsdnProtocol/libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolSettersLibrary as Setters } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolSettersLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { PriceInfo } from "../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../../../src/libraries/DoubleEndedQueue.sol";
import { SignedMath } from "../../../src/libraries/SignedMath.sol";
import { TickMath } from "../../../src/libraries/TickMath.sol";

/**
 * @title UsdnProtocolHandler
 *
 * @dev Wrapper to aid in testing the protocol
 * @custom:fuzzing external funciton => external
 * @custom:fuzzing added getters
 */
contract UsdnProtocolHandler is UsdnProtocolImpl, Test {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    Storage _tempStorage;

    function initializeStorageHandler(InitStorage calldata initStorage) external initializer {
        initializeStorage(initStorage);
    }

    /*
     * @custom:fuzzing Added fuzzing helpers
     */

    function getHighestPopulatedTick() external view returns (int24) {
        Storage storage s = Utils._getMainStorage();

        return s._highestPopulatedTick;
    }

    function getBitmapAtIndex(uint256 index) external view returns (bool) {
        Storage storage s = Utils._getMainStorage();

        return s._tickBitmap.get(index);
    }

    function getTickHash(int24 tick) external view returns (bytes32 hash, uint256 version) {
        Storage storage s = Utils._getMainStorage();

        version = s._tickVersion[tick];
        hash = Utils._tickHash(tick, version);
        return (hash, version);
    }

    function getTickData(bytes32 tickHash) external view returns (Types.TickData memory) {
        Storage storage s = Utils._getMainStorage();

        return s._tickData[tickHash];
    }

    function getPosition(bytes32 tickHash, uint256 index) external view returns (Types.Position memory) {
        Storage storage s = Utils._getMainStorage();

        return s._longPositions[tickHash][index];
    }

    function getTickVersion(int24 tick) external view returns (uint256) {
        Storage storage s = Utils._getMainStorage();

        return s._tickVersion[tick];
    }

    function getBitmapIndex(int24 tick) external view returns (uint256) {
        return Utils._calcBitmapIndexFromTick(tick);
    }

    function getMaxTick() external pure returns (int24) {
        return TickMath.MAX_TICK;
    }

    function getMinTick() external pure returns (int24) {
        return TickMath.MIN_TICK;
    }

    function checkNumOfPositions() public view returns (uint256) {
        Storage storage s = Utils._getMainStorage();

        return s._totalLongPositions;
    }

    function getPositionOwner(Types.PositionId memory posId) external view returns (address) {
        Storage storage s = Utils._getMainStorage();

        (bytes32 tickHash, uint256 currentVersion) = Utils._tickHash(posId.tick);

        require(currentVersion == posId.tickVersion, "UsdnHandler::getPositionOwner position not found or liquidated");

        Types.Position storage position = s._longPositions[tickHash][posId.index];
        return position.user;
    }

    function checkForLiquidations(uint256 currentPrice) external returns (bool) {
        Storage storage s = Utils._getMainStorage();

        bool _positionLiquidatedTemp = s._positionLiquidated;
        s._positionLiquidated = false;
        return _positionLiquidatedTemp;
    }

    function checkForLiquidationsInActions() external returns (bool) {
        Storage storage s = Utils._getMainStorage();

        bool _positionWasLiquidatedInTheMeantime = s._positionWasLiquidatedInTheMeantime;
        s._positionWasLiquidatedInTheMeantime = false;
        return _positionWasLiquidatedInTheMeantime;
    }

    function checkForLiquidationPending() external returns (bool) {
        Storage storage s = Utils._getMainStorage();

        bool _liquidationPending = s._liquidationPending;
        s._liquidationPending = false;
        return _liquidationPending;
    }

    function checkIfRebalancerTriggered() external returns (bool) {
        Storage storage s = Utils._getMainStorage();

        bool _rebalancerTriggered = s._rebalancerTriggered;
        s._rebalancerTriggered = false;
        return _rebalancerTriggered;
    }

    function checkForLiquidatorAddressAndReward() external returns (address, uint256) {
        Storage storage s = Utils._getMainStorage();

        address _fuzz_liquidator = s._fuzz_liquidator;
        uint256 _fuzz_liquidationRewards = s._fuzz_liquidationRewards;
        s._fuzz_liquidator = address(0);
        s._fuzz_liquidationRewards = 0;
        return (_fuzz_liquidator, _fuzz_liquidationRewards);
    }

    function checkLiquidatedTicks() external returns (int24) {
        Storage storage s = Utils._getMainStorage();

        int24 lowestLiquidatedTick = s._lowestLiquidatedTick;

        s._lowestLiquidatedTick = 0;

        return (lowestLiquidatedTick);
    }

    function checkForPositionProfit() external returns (int256) {
        Storage storage s = Utils._getMainStorage();

        int256 _positionProfit = s._positionProfit;
        s._positionProfit = 0;
        return _positionProfit;
    }

    function checkLatestPositionTick() external returns (int24) {
        Storage storage s = Utils._getMainStorage();

        int24 latestPositionTick = s._latestPosIdTIck;
        s._latestPosIdTIck = 0;
        return latestPositionTick;
    }

    function checkWithdrawalAmount() external returns (uint256) {
        Storage storage s = Utils._getMainStorage();

        uint256 withdrawAssetToTransferAfterFees = s._withdrawAssetToTransferAfterFees;
        s._withdrawAssetToTransferAfterFees = 0;
        return withdrawAssetToTransferAfterFees;
    }

    /// @dev Useful to completely disable funding, which is normally initialized with a positive bias value
    function resetEMA() external {
        Storage storage s = Utils._getMainStorage();

        s._EMA = 0;
    }

    /// @dev Push a pending item to the front of the pending actions queue
    function queuePushFront(PendingAction memory action) external returns (uint128 rawIndex_) {
        Storage storage s = Utils._getMainStorage();

        rawIndex_ = s._pendingActionsQueue.pushFront(action);
        s._pendingActions[action.validator] = uint256(rawIndex_) + 1;
    }

    /// @dev Verify if the pending actions queue is empty
    function queueEmpty() external view returns (bool) {
        Storage storage s = Utils._getMainStorage();

        return s._pendingActionsQueue.empty();
    }

    function getQueueItem(uint128 rawIndex) external view returns (PendingAction memory) {
        Storage storage s = Utils._getMainStorage();

        return s._pendingActionsQueue.atRaw(rawIndex);
    }

    /**
     * @dev Use this function in unit tests to make sure we provide a fresh price that updates the balances
     * The function reverts the price given by the mock oracle middleware is not fresh enough to trigger a balance
     * update. Call `_waitBeforeLiquidation()` before calling this function to make sure enough time has passed.
     * Do not use this function in contexts where ether needs to be refunded.
     */
    function mockLiquidate(bytes calldata currentPriceData)
        external
        payable
        returns (Types.LiqTickInfo[] memory liquidatedTicks_)
    {
        Storage storage s = Utils._getMainStorage();

        uint256 lastUpdateTimestampBefore = s._lastUpdateTimestamp;
        vm.startPrank(msg.sender);
        liquidatedTicks_ = this.liquidate(currentPriceData);
        vm.stopPrank();
        require(s._lastUpdateTimestamp > lastUpdateTimestampBefore, "UsdnProtocolHandler: liq price is not fresh");
    }

    function tickValue(int24 tick, uint256 currentPrice) external view returns (int256) {
        Storage storage s = Utils._getMainStorage();

        uint256 longTradingExpo = this.longTradingExpoWithFunding(uint128(currentPrice), uint128(block.timestamp));
        bytes32 tickHash = Utils._tickHash(tick, s._tickVersion[tick]);
        return Long._tickValue(tick, currentPrice, longTradingExpo, s._liqMultiplierAccumulator, s._tickData[tickHash]);
    }

    /**
     * @dev Helper function to simulate a situation where the vault would be empty. In practice, it's not possible to
     * achieve.
     */
    function emptyVault() external {
        Storage storage s = Utils._getMainStorage();

        s._balanceLong += s._balanceVault;
        s._balanceVault = 0;
    }

    function removePendingAction(uint128 rawIndex, address user) external {
        Storage storage s = Utils._getMainStorage();

        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    function i_createWithdrawalPendingAction(
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        Vault.WithdrawalData memory data
    ) public returns (uint256 amountToRefund_) {
        return Core._createWithdrawalPendingAction(to, validator, usdnShares, securityDepositValue, data);
    }

    function i_createDepositPendingAction(
        address validator,
        address to,
        uint64 securityDepositValue,
        uint128 amount,
        Vault.InitiateDepositData memory data
    ) external returns (uint256 amountToRefund_) {
        return Vault._createDepositPendingAction(validator, to, securityDepositValue, amount, data);
    }

    function i_createOpenPendingAction(
        address to,
        address validator,
        uint64 securityDepositValue,
        InitiateOpenPositionData memory data
    ) public returns (uint256 amountToRefund_) {
        return Core._createOpenPendingAction(to, validator, securityDepositValue, data);
    }

    function i_createClosePendingAction(
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        ClosePositionData memory data
    ) external returns (uint256 amountToRefund_) {
        return Core._createClosePendingAction(to, validator, posId, amountToClose, securityDepositValue, data);
    }

    function findLastSetInTickBitmap(int24 searchFrom) external view returns (uint256 index) {
        Storage storage s = Utils._getMainStorage();

        return s._tickBitmap.findLastSet(Utils._calcBitmapIndexFromTick(searchFrom));
    }

    function tickBitmapStatus(int24 tick) external view returns (bool isSet_) {
        Storage storage s = Utils._getMainStorage();

        return s._tickBitmap.get(Utils._calcBitmapIndexFromTick(tick));
    }

    function setTickVersion(int24 tick, uint256 version) external {
        Storage storage s = Utils._getMainStorage();

        s._tickVersion[tick] = version;
    }

    function setPendingProtocolFee(uint256 value) external {
        Storage storage s = Utils._getMainStorage();

        s._pendingProtocolFee = value;
    }

    /**
     * @notice Helper to calculate the trading exposure of the long side at the time of the last balance update and
     * currentPrice
     */
    function getLongTradingExpo(uint128 currentPrice) external view returns (uint256 expo_) {
        Storage storage s = Utils._getMainStorage();

        expo_ = uint256(s._totalExpo.toInt256().safeSub(Utils._longAssetAvailable(currentPrice)));
    }

    function _calcEMA(int256 lastFundingPerDay, uint128 secondsElapsed) external view returns (int256) {
        Storage storage s = Utils._getMainStorage();

        return Core._calcEMA(lastFundingPerDay, secondsElapsed, s._EMAPeriod, s._EMA);
    }

    function i_validateClosePosition(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        return ActionsLong._validateClosePosition(user, priceData);
    }

    function i_validateWithdrawal(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        return Vault._validateWithdrawal(user, priceData);
    }

    function i_validateDeposit(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        return Vault._validateDeposit(user, priceData);
    }

    function i_removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) external returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        liqMultiplierAccumulator_ = Long._removeAmountFromPosition(tick, index, pos, amountToRemove, totalExpoToRemove);
    }

    function i_positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (int256 value_)
    {
        return Utils._positionValue(currentPrice, liqPriceWithoutPenalty, positionTotalExpo);
    }

    function i_calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
    {
        return Utils._calcPositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    function i_getActionablePendingAction() external returns (PendingAction memory, uint128) {
        return Vault._getActionablePendingAction();
    }

    function i_lastFundingPerDay() external view returns (int256) {
        Storage storage s = Utils._getMainStorage();

        return s._lastFundingPerDay;
    }

    function i_toWithdrawalPendingAction(PendingAction memory action)
        external
        pure
        returns (WithdrawalPendingAction memory)
    {
        return Utils._toWithdrawalPendingAction(action);
    }

    function i_toLongPendingAction(PendingAction memory action) external pure returns (LongPendingAction memory) {
        return Utils._toLongPendingAction(action);
    }

    function i_convertDepositPendingAction(DepositPendingAction memory action)
        external
        pure
        returns (PendingAction memory)
    {
        return Utils._convertDepositPendingAction(action);
    }

    function i_convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        external
        pure
        returns (PendingAction memory)
    {
        return Utils._convertWithdrawalPendingAction(action);
    }

    function i_convertLongPendingAction(LongPendingAction memory action) external pure returns (PendingAction memory) {
        return Utils._convertLongPendingAction(action);
    }

    function i_assetToRemove(
        uint256 balanceLong,
        uint128 priceWithFees,
        uint128 liqPriceWithoutPenalty,
        uint128 posExpo
    ) external pure returns (uint256) {
        return ActionsUtils._assetToRemove(balanceLong, priceWithFees, liqPriceWithoutPenalty, posExpo);
    }

    function i_tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) public pure returns (int256) {
        return Long._tickValue(tick, currentPrice, longTradingExpo, accumulator, tickData);
    }

    function i_getOraclePrice(ProtocolAction action, uint256 timestamp, bytes32 actionId, bytes calldata priceData)
        external
        payable
        returns (PriceInfo memory)
    {
        return Utils._getOraclePrice(action, timestamp, actionId, priceData);
    }

    function i_applyPnlAndFundingStateless(uint128 currentPrice, uint128 timestamp)
        public
        returns (ApplyPnlAndFundingData memory data_)
    {
        return Core._applyPnlAndFundingStateless(currentPrice, timestamp);
    }

    function i_calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) external pure returns (uint256) {
        return Utils._calcSdexToBurn(usdnAmount, sdexBurnRatio);
    }

    function i_vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) external pure returns (int256 available_) {
        return Utils._vaultAssetAvailable(totalExpo, balanceVault, balanceLong, newPrice, oldPrice);
    }

    function i_vaultAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return Vault._vaultAssetAvailable(currentPrice);
    }

    function i_tickHash(int24 tick) external view returns (bytes32, uint256) {
        return Utils._tickHash(tick);
    }

    function i_longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        external
        pure
        returns (int256 available_)
    {
        return Utils._longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);
    }

    function i_longAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return Utils._longAssetAvailable(currentPrice);
    }

    function i_getLiquidationPrice(uint128 startPrice, uint128 leverage) external pure returns (uint128) {
        return Utils._getLiquidationPrice(startPrice, leverage);
    }

    function i_checkImbalanceLimitDeposit(uint256 depositValue) external view {
        ActionsUtils._checkImbalanceLimitDeposit(depositValue);
    }

    function i_checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) external view {
        ActionsUtils._checkImbalanceLimitWithdrawal(withdrawalValue, totalExpo);
    }

    function i_checkImbalanceLimitClose(uint256 posTotalExpoToClose, uint256 posValueToClose) external view {
        ActionsUtils._checkImbalanceLimitClose(posTotalExpoToClose, posValueToClose);
    }

    function i_getLeverage(uint128 price, uint128 liqPrice) external pure returns (uint256) {
        return Utils._getLeverage(price, liqPrice);
    }

    function i_calcTickFromBitmapIndex(uint256 index) public view returns (int24) {
        return Long._calcTickFromBitmapIndex(index);
    }

    function i_calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) public pure returns (int24) {
        return Long._calcTickFromBitmapIndex(index, tickSpacing);
    }

    function i_calcBitmapIndexFromTick(int24 tick) external view returns (uint256) {
        return Utils._calcBitmapIndexFromTick(tick);
    }

    function i_calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) external pure returns (uint256) {
        return Utils._calcBitmapIndexFromTick(tick, tickSpacing);
    }

    function i_calcLiqPriceFromTradingExpo(uint128 currentPrice, uint128 amount, uint256 tradingExpo)
        external
        pure
        returns (uint128 liqPrice_)
    {
        return Long._calcLiqPriceFromTradingExpo(currentPrice, amount, tradingExpo);
    }

    function i_findHighestPopulatedTick(int24 searchStart) external view returns (int24 tick_) {
        return Long._findHighestPopulatedTick(searchStart);
    }

    function i_updateEMA(int256 fundingPerDay, uint128 secondsElapsed) external {
        Core._updateEMA(fundingPerDay, secondsElapsed);
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
        return Long._calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
    }

    function i_addPendingAction(address user, PendingAction memory action) external returns (uint256) {
        return Core._addPendingAction(user, action);
    }

    function i_getPendingAction(address user) external view returns (PendingAction memory, uint128) {
        return Core._getPendingAction(user);
    }

    function i_getPendingActionOrRevert(address user) external view returns (PendingAction memory, uint128) {
        return Core._getPendingActionOrRevert(user);
    }

    function i_executePendingAction(PreviousActionsData calldata data) external returns (bool, bool, bool, uint256) {
        return Vault._executePendingAction(data);
    }

    function i_executePendingActionOrRevert(PreviousActionsData calldata data) external {
        Vault._executePendingActionOrRevert(data);
    }

    function i_refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore)
        external
        payable
    {
        Utils._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
    }

    function i_refundEther(uint256 amount, address payable to) external payable {
        Utils._refundEther(amount, to);
    }

    function i_mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB) external pure returns (uint256) {
        return Utils._mergeWithdrawalAmountParts(sharesLSB, sharesMSB);
    }

    function i_calcWithdrawalAmountLSB(uint152 usdnShares) external pure returns (uint24) {
        return Vault._calcWithdrawalAmountLSB(usdnShares);
    }

    function i_calcWithdrawalAmountMSB(uint152 usdnShares) external pure returns (uint128) {
        return Vault._calcWithdrawalAmountMSB(usdnShares);
    }

    function i_createInitialDeposit(uint128 amount, uint128 price) external {
        Core._createInitialDeposit(amount, price);
    }

    function i_createInitialPosition(uint128 amount, uint128 price, int24 tick, uint128 positionTotalExpo) external {
        Core._createInitialPosition(amount, price, tick, positionTotalExpo);
    }

    function i_checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) external view {
        Long._checkSafetyMargin(currentPrice, liquidationPrice);
    }

    function i_getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) external pure returns (uint128) {
        return Utils._getEffectivePriceForTick(tick, liqMultiplier);
    }

    function i_calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint256) {
        return Utils._calcFixedPrecisionMultiplier(assetPrice, longTradingExpo, accumulator);
    }

    function i_calcTickWithoutPenalty(int24 tick, uint24 liquidationPenalty) external pure returns (int24) {
        return Utils._calcTickWithoutPenalty(tick, liquidationPenalty);
    }

    function i_calcTickWithoutPenalty(int24 tick) external view returns (int24) {
        Storage storage s = Utils._getMainStorage();

        return Utils._calcTickWithoutPenalty(tick, s._liquidationPenalty);
    }

    function i_unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint256) {
        return Long._unadjustPrice(price, assetPrice, longTradingExpo, accumulator);
    }

    function i_adjustPrice(
        uint256 unadjustedPrice,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure {
        Utils._adjustPrice(unadjustedPrice, assetPrice, longTradingExpo, accumulator);
    }

    function i_clearPendingAction(address user, uint128 rawIndex) external {
        Utils._clearPendingAction(user, rawIndex);
    }

    function i_calcRebalancerPositionTick(
        uint128 neutralPrice,
        uint128 positionAmount,
        uint256 rebalancerMaxLeverage,
        uint256 totalExpo,
        uint256 balanceLong,
        uint256 balanceVault,
        HugeUint.Uint512 memory liqMultiplierAccumulator
    ) external view returns (int24 tick_, uint128 totalExpo_, uint24 liquidationPenalty_) {
        CachedProtocolState memory cache = CachedProtocolState({
            totalExpo: totalExpo,
            longBalance: balanceLong,
            vaultBalance: balanceVault,
            tradingExpo: totalExpo - balanceLong,
            liqMultiplierAccumulator: liqMultiplierAccumulator
        });

        Types.RebalancerPositionData memory position =
            Long._calcRebalancerPositionTick(neutralPrice, positionAmount, rebalancerMaxLeverage, cache);

        return (position.tick, position.totalExpo, position.liquidationPenalty);
    }

    function i_calcImbalanceCloseBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_)
    {
        return Utils._calcImbalanceCloseBps(vaultBalance, longBalance, longTotalExpo);
    }

    function i_calcImbalanceOpenBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_)
    {
        return Long._calcImbalanceOpenBps(vaultBalance, longBalance, longTotalExpo);
    }

    function i_removeBlockedPendingAction(uint128 rawIndex, address payable to, bool cleanup) external {
        Core._removeBlockedPendingAction(rawIndex, to, cleanup);
    }

    function i_checkInitImbalance(uint128 positionTotalExpo, uint128 longAmount, uint128 depositAmount) external view {
        Core._checkInitImbalance(positionTotalExpo, longAmount, depositAmount);
    }

    function i_removeStalePendingAction(address user) external returns (uint256) {
        return Core._removeStalePendingAction(user);
    }

    function i_triggerRebalancer(
        uint128 lastPrice,
        uint256 longBalance,
        uint256 vaultBalance,
        int256 remainingCollateral
    ) public returns (uint256 longBalance_, uint256 vaultBalance_, Types.RebalancerAction rebalancerAction_) {
        return Long._triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);
    }

    function i_calculateFee(int256 fundAsset) external returns (int256 fee_, int256 fundAssetWithFee_) {
        return Core._calculateFee(fundAsset);
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

        return Long._flashClosePosition(posId, neutralPrice, cache);
    }

    function i_flashOpenPosition(
        address user,
        uint128 neutralPrice,
        int24 tick,
        uint128 posTotalExpo,
        uint24 liquidationPenalty,
        uint128 amount
    ) external returns (PositionId memory posId_) {
        return Long._flashOpenPosition(user, neutralPrice, tick, posTotalExpo, liquidationPenalty, amount);
    }

    function i_checkPendingFee() external {
        Utils._checkPendingFee();
    }

    function i_sendRewardsToLiquidator(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        uint256 currentPrice,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        ProtocolAction action,
        bytes memory rebaseCallbackResult,
        bytes memory priceData
    ) external {
        Long._sendRewardsToLiquidator(
            liquidatedTicks, currentPrice, rebased, rebalancerAction, action, rebaseCallbackResult, priceData
        );
    }

    function i_prepareInitiateDepositData(
        address validator,
        uint128 amount,
        uint256 sharesOutMin,
        bytes calldata currentPriceData
    ) public returns (Vault.InitiateDepositData memory data_) {
        return Vault._prepareInitiateDepositData(validator, amount, sharesOutMin, currentPriceData);
    }

    function i_prepareWithdrawalData(
        address validator,
        uint152 usdnShares,
        uint256 amountOutMin,
        bytes calldata currentPriceData
    ) public returns (Vault.WithdrawalData memory data_) {
        return Vault._prepareWithdrawalData(validator, usdnShares, amountOutMin, currentPriceData);
    }

    function i_prepareValidateOpenPositionData(PendingAction memory pending, bytes calldata priceData)
        external
        returns (ValidateOpenPositionData memory data_, bool liquidated_)
    {
        return ActionsLong._prepareValidateOpenPositionData(pending, priceData);
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

    function i_fundingAsset(uint128 timestamp, int256 ema)
        external
        view
        returns (int256 fundingAsset, int256 fundingPerDay)
    {
        return Core._fundingAsset(timestamp, ema);
    }

    function i_fundingPerDay(int256 ema) external view returns (int256 fundingPerDay_, int256 oldLongExpo_) {
        return Core._fundingPerDay(ema);
    }

    function i_protocolFeeBps() external view returns (uint16) {
        Storage storage s = Utils._getMainStorage();

        return s._protocolFeeBps;
    }

    function i_getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
        return Long._getTickFromDesiredLiqPrice(
            desiredLiqPriceWithoutPenalty, assetPrice, longTradingExpo, accumulator, tickSpacing, liquidationPenalty
        );
    }

    function i_getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 liqMultiplier,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
        return Long._getTickFromDesiredLiqPrice(
            desiredLiqPriceWithoutPenalty, liqMultiplier, tickSpacing, liquidationPenalty
        );
    }

    function i_calcMaxLongBalance(uint256 totalExpo) external pure returns (uint256) {
        return Core._calcMaxLongBalance(totalExpo);
    }

    function i_toDepositPendingAction(PendingAction memory action)
        external
        pure
        returns (DepositPendingAction memory)
    {
        return Utils._toDepositPendingAction(action);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */

    function getValidatorDeadlines(uint256 seed)
        external
        view
        returns (uint128 lowLatencyDeadline, uint128 onChainDeadline)
    {
        Storage storage s = Utils._getMainStorage();

        uint256 seed1 = uint128(seed); // Lower 128 bits
        uint256 seed2 = uint128(seed >> 128); // Upper 128 bits

        lowLatencyDeadline =
            uint128(bound(seed1, Constants.MIN_VALIDATION_DEADLINE, s._oracleMiddleware.getLowLatencyDelay()));
        onChainDeadline = uint128(bound(seed2, 0, Constants.MAX_VALIDATION_DEADLINE));
    }

    function getMinLeverage(uint256 seed) external view returns (uint256 minLeverage) {
        Storage storage s = Utils._getMainStorage();

        minLeverage = bound(seed, (10 ** Constants.LEVERAGE_DECIMALS) + 1, s._maxLeverage - 1);
    }

    function getMaxLeverage(uint256 seed) external view returns (uint256 maxLeverage) {
        Storage storage s = Utils._getMainStorage();

        maxLeverage = bound(seed, s._minLeverage + 1, Constants.MAX_LEVERAGE);
    }

    function getLiquidationPenalty(uint256 seed) external pure returns (uint24 liquidationPenalty) {
        liquidationPenalty = uint24(bound(seed, 0, Constants.MAX_LIQUIDATION_PENALTY));
    }

    function getEMAPeriod(uint256 seed) external pure returns (uint128 EMAPeriod) {
        EMAPeriod = uint128(bound(seed, 0, Constants.MAX_EMA_PERIOD));
    }

    function getFundingSF(uint256 seed) external pure returns (uint256 fundingSF) {
        fundingSF = bound(seed, 0, 10 ** Constants.FUNDING_SF_DECIMALS);
    }

    function getProtocolFeeBps(uint256 seed) external pure returns (uint16 protocolFeeBps) {
        protocolFeeBps = uint16(bound(seed, 0, Constants.MAX_PROTOCOL_FEE_BPS));
    }

    function getPositionFeeBps(uint256 seed) external pure returns (uint16 positionFee) {
        positionFee = uint16(bound(seed, 0, Constants.MAX_POSITION_FEE_BPS));
    }

    function getVaultFeeBps(uint256 seed) external pure returns (uint16 vaultFee) {
        vaultFee = uint16(bound(seed, 0, Constants.MAX_VAULT_FEE_BPS));
    }

    function getSdexRewardsRatioBps(uint256 seed) external pure returns (uint16 rewards) {
        rewards = uint16(bound(seed, 0, Constants.MAX_SDEX_REWARDS_RATIO_BPS));
    }

    function getRebalancerBonusBps(uint256 seed) external pure returns (uint16 bonus) {
        bonus = uint16(bound(seed, 0, Constants.BPS_DIVISOR));
    }

    function getSdexBurnOnDepositRatio(uint256 seed) external pure returns (uint32 ratio) {
        ratio = uint32(bound(seed, 0, Constants.MAX_SDEX_BURN_RATIO));
    }

    function getSecurityDepositValue(uint256 seed) external pure returns (uint64 securityDeposit) {
        securityDeposit = uint64(bound(seed, 0, Constants.MAX_SECURITY_DEPOSIT));
    }

    // @todo make dynamic with seeds
    function getExpoImbalanceLimits(
        uint256 seed1,
        uint256 seed2,
        uint256 seed3,
        uint256 seed4,
        uint256 seed5,
        int256 seed6
    )
        external
        pure
        returns (
            uint256 openLimit,
            uint256 depositLimit,
            uint256 withdrawalLimit,
            uint256 closeLimit,
            uint256 rebalancerCloseLimit,
            int256 longImbalanceTarget
        )
    {
        openLimit = 5000;
        depositLimit = 3000;
        withdrawalLimit = 5000;
        closeLimit = 3000;
        rebalancerCloseLimit = 0;

        if (seed6 < 0) {
            longImbalanceTarget = -1000; // Well above -5000 and -withdrawalLimit
        } else {
            longImbalanceTarget = 1000; // Well below closeLimit (3000)
        }

        return (openLimit, depositLimit, withdrawalLimit, closeLimit, rebalancerCloseLimit, longImbalanceTarget);
    }

    function getMinLongPosition(uint256 seed) external pure returns (uint256 minLongPosition) {
        minLongPosition = bound(seed, 0, Constants.MAX_MIN_LONG_POSITION);
    }

    function getSafetyMarginBps(uint256 seed) external pure returns (uint256 safetyMarginBps) {
        safetyMarginBps = bound(seed, 0, Constants.MAX_SAFETY_MARGIN_BPS);
    }

    function getLiquidationIteration(uint256 seed) external pure returns (uint16 liquidationIteration) {
        liquidationIteration = uint16(bound(seed, 0, Constants.MAX_LIQUIDATION_ITERATION));
    }

    function getTargetUsdnPrice(uint256 seed) external view returns (uint128 price) {
        Types.Storage storage s = Utils._getMainStorage();
        uint128 minPrice = uint128(10 ** s._priceFeedDecimals);
        uint128 maxPrice = s._usdnRebaseThreshold;

        price = uint128(bound(seed, minPrice, maxPrice));
    }

    function getUsdnRebaseThreshold(uint256 seed) external view returns (uint128 threshold) {
        Types.Storage storage s = Utils._getMainStorage();
        uint128 minThreshold = s._targetUsdnPrice;
        uint128 maxThreshold = uint128(2 * 10 ** s._priceFeedDecimals);

        threshold = uint128(bound(seed, minThreshold, maxThreshold));
    }
}
