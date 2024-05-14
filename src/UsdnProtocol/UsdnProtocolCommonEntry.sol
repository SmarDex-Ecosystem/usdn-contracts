// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {
    Position,
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    LiquidationsEffects,
    PreviousActionsData,
    PositionId,
    TickData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { UsdnProtocolCommonLibrary as lib } from "src/UsdnProtocol/UsdnProtocolCommonLibrary.sol";

abstract contract UsdnProtocolCommonEntry is UsdnProtocolBaseStorage {
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        pure
        returns (int256)
    {
        return lib.calcEMA(lastFunding, secondsElapsed, emaPeriod, previousEMA);
    }

    function getEffectiveTickForPrice(uint128 price) public view returns (int24 tick_) {
        return lib.getEffectiveTickForPrice(s, price);
    }

    function funding(uint128 timestamp) public view returns (int256 fund_, int256 oldLongExpo_) {
        return lib.funding(s, timestamp);
    }

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) public pure returns (int24 tick_) {
        return lib.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
    }

    function getTickLiquidationPenalty(int24 tick) public view returns (uint8 liquidationPenalty_) {
        return lib.getTickLiquidationPenalty(s, tick);
    }

    function getEffectivePriceForTick(int24 tick) public view returns (uint128 price_) {
        return lib.getEffectivePriceForTick(s, tick);
    }

    function _calculatePositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        public
        pure
        returns (uint128 totalExpo_)
    {
        return lib._calculatePositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    function _saveNewPosition(int24 tick, Position memory long, uint8 liquidationPenalty)
        internal
        returns (uint256 tickVersion_, uint256 index_)
    {
        return lib._saveNewPosition(s, tick, long, liquidationPenalty);
    }

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        return lib.getEffectivePriceForTick(tick, assetPrice, longTradingExpo, accumulator);
    }

    function _getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        public
        returns (PriceInfo memory price_)
    {
        return lib._getOraclePrice(s, action, timestamp, priceData);
    }

    function minTick() public view returns (int24 tick_) {
        return lib.minTick(s);
    }

    function _unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal pure returns (uint256 unadjustedPrice_) {
        return lib._unadjustPrice(price, assetPrice, longTradingExpo, accumulator);
    }

    function _calcTickWithoutPenalty(int24 tick, uint8 liquidationPenalty) internal view returns (int24 tick_) {
        return lib._calcTickWithoutPenalty(s, tick, liquidationPenalty);
    }

    function _calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        internal
        pure
        returns (uint256 assetExpected_)
    {
        return lib._calcBurnUsdn(usdnShares, available, usdnTotalShares);
    }

    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) internal view returns (uint128 price_) {
        return lib._getEffectivePriceForTick(s, tick, liqMultiplier);
    }

    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        internal
        view
        returns (uint256 toMint_)
    {
        return lib._calcMintUsdn(s, amount, vaultBalance, usdnTotalSupply, price);
    }

    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        internal
        pure
        returns (uint256 usdnShares_)
    {
        return lib._mergeWithdrawalAmountParts(sharesLSB, sharesMSB);
    }

    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore) internal {
        return lib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
    }

    function _calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        internal
        view
        returns (uint256 totalSupply_)
    {
        return lib._calcRebaseTotalSupply(s, vaultBalance, assetPrice, targetPrice, assetDecimals);
    }

    function _calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        internal
        view
        returns (uint256 price_)
    {
        return lib._calcUsdnPrice(s, vaultBalance, assetPrice, usdnTotalSupply, assetDecimals);
    }

    function _usdnRebase(uint128 assetPrice, bool ignoreInterval) internal returns (bool rebased_) {
        return lib._usdnRebase(s, assetPrice, ignoreInterval);
    }

    function _updateEMA(uint128 secondsElapsed) internal returns (int256) {
        return lib._updateEMA(s, secondsElapsed);
    }

    function _calcBitmapIndexFromTick(int24 tick) internal view returns (uint256 index_) {
        return lib._calcBitmapIndexFromTick(s, tick);
    }

    function _findHighestPopulatedTick(int24 searchStart) internal view returns (int24 tick_) {
        return lib._findHighestPopulatedTick(s, searchStart);
    }

    function _calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) internal pure returns (int24 tick_) {
        return lib._calcTickFromBitmapIndex(index, tickSpacing);
    }

    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal view returns (uint128 leverage_) {
        return lib._getLeverage(s, startPrice, liquidationPrice);
    }

    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal view returns (uint128 price_) {
        return lib._getLiquidationPrice(s, startPrice, leverage);
    }

    function _longAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        return lib._longAssetAvailable(s, currentPrice);
    }

    function _tickHash(int24 tick) internal view returns (bytes32 hash_, uint256 version_) {
        return lib._tickHash(s, tick);
    }

    function _tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) internal view returns (int256 value_) {
        return lib._tickValue(s, tick, currentPrice, longTradingExpo, accumulator, tickData);
    }

    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        internal
        returns (bool priceUpdated_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        return lib._applyPnlAndFunding(s, currentPrice, timestamp);
    }

    function _positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        internal
        pure
        returns (int256 value_)
    {
        return lib._positionValue(currentPrice, liqPriceWithoutPenalty, positionTotalExpo);
    }

    function _removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) internal {
        return lib._removeAmountFromPosition(s, tick, index, pos, amountToRemove, totalExpoToRemove);
    }

    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) internal pure returns (int256 available_) {
        return lib._vaultAssetAvailable(totalExpo, balanceVault, balanceLong, newPrice, oldPrice);
    }

    function _calcTickFromBitmapIndex(uint256 index) internal view returns (int24 tick_) {
        return lib._calcTickFromBitmapIndex(s, index);
    }

    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) internal pure returns (uint256 index_) {
        return lib._calcBitmapIndexFromTick(tick, tickSpacing);
    }
}
