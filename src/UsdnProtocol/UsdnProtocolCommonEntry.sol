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
import { IUsdnProtocolCommon } from "src/interfaces/UsdnProtocol/IUsdnProtocolCommon.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

abstract contract UsdnProtocolCommonEntry is UsdnProtocolBaseStorage, InitializableReentrancyGuard {
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        returns (int256)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon.calcEMA.selector, lastFunding, secondsElapsed, emaPeriod, previousEMA
            )
        );
        require(success, "failed");
        return abi.decode(data, (int256));
    }

    function getEffectiveTickForPrice(uint128 price) public returns (int24 tick_) {
        (bool success, bytes memory data) =
        // TO DO : check if we can use selector
         address(s._protocol).delegatecall(abi.encodeWithSignature("getEffectiveTickForPrice(uint128)", price));
        require(success, "failed");
        tick_ = abi.decode(data, (int24));
    }

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) public returns (int24 tick_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            // TO DO : same
            abi.encodeWithSignature(
                "getEffectiveTickForPrice(uint128,uint256,uint256,HugeUint.Uint512,int24",
                price,
                assetPrice,
                longTradingExpo,
                accumulator,
                tickSpacing
            )
        );
        require(success, "failed");
        tick_ = abi.decode(data, (int24));
    }

    function getTickLiquidationPenalty(int24 tick) public returns (uint8 liquidationPenalty_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon.getTickLiquidationPenalty.selector, tick)
        );
        require(success, "failed");
        liquidationPenalty_ = abi.decode(data, (uint8));
    }

    function getEffectivePriceForTick(int24 tick) public returns (uint128 price_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSignature("getEffectivePriceForTick(int24)", tick));
        require(success, "failed");
        price_ = abi.decode(data, (uint128));
    }

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public returns (uint128 price_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSignature(
                "getEffectivePriceForTick(int24,uint256,uint256,HugeUint.Uint512)",
                tick,
                assetPrice,
                longTradingExpo,
                accumulator
            )
        );
        require(success, "failed");
        price_ = abi.decode(data, (uint128));
    }

    function _getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        public
        returns (PriceInfo memory price_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._getOraclePrice.selector, action, timestamp, priceData)
        );
        require(success, "failed");
        price_ = abi.decode(data, (PriceInfo));
    }

    function minTick() public returns (int24 tick_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSelector(IUsdnProtocolCommon.minTick.selector, tick_));
        require(success, "failed");
        tick_ = abi.decode(data, (int24));
    }

    function _unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal returns (uint256 unadjustedPrice_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._unadjustPrice.selector, price, assetPrice, longTradingExpo, accumulator
            )
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _calcTickWithoutPenalty(int24 tick, uint8 liquidationPenalty) internal returns (int24 tick_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._calcTickWithoutPenalty.selector, tick, liquidationPenalty)
        );
        require(success, "failed");
        return abi.decode(data, (int24));
    }

    function _calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        internal
        returns (uint256 assetExpected_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._calcBurnUsdn.selector, usdnShares, available, usdnTotalShares)
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) internal returns (uint128 price_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._getEffectivePriceForTick.selector, tick, liqMultiplier)
        );
        require(success, "failed");
        return abi.decode(data, (uint128));
    }

    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        internal
        returns (uint256 toMint_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._calcMintUsdn.selector, amount, vaultBalance, usdnTotalSupply, price
            )
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB) internal returns (uint256 usdnShares_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._mergeWithdrawalAmountParts.selector, sharesLSB, sharesMSB)
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore) internal {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._refundExcessEther.selector, securityDepositValue, amountToRefund, balanceBefore
            )
        );
        require(success, "failed");
    }

    function _executePendingActionOrRevert(PreviousActionsData calldata data)
        internal
        returns (uint256 securityDepositValue_)
    {
        (bool success, bytes memory returnedData) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._executePendingActionOrRevert.selector, data)
        );
        require(success, "failed");
        return abi.decode(returnedData, (uint256));
    }

    function _executePendingAction(PreviousActionsData calldata data)
        internal
        returns (bool success_, bool executed_, uint256 securityDepositValue_)
    {
        (bool success, bytes memory returnedData) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._executePendingAction.selector, data)
        );
        require(success, "failed");
        return abi.decode(returnedData, (bool, bool, uint256));
    }

    function _getPendingAction(address user) internal returns (PendingAction memory action_, uint128 rawIndex_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._getPendingAction.selector, user)
        );
        require(success, "failed");
        return abi.decode(data, (PendingAction, uint128));
    }

    function _addPendingAction(address user, PendingAction memory action)
        internal
        returns (uint256 securityDepositValue_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._addPendingAction.selector, user, action)
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        internal
        returns (uint256 totalSupply_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._calcRebaseTotalSupply.selector,
                vaultBalance,
                assetPrice,
                targetPrice,
                assetDecimals
            )
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        internal
        returns (uint256 price_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._calcUsdnPrice.selector, vaultBalance, assetPrice, usdnTotalSupply, assetDecimals
            )
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _usdnRebase(uint128 assetPrice, bool ignoreInterval) internal returns (bool rebased_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._usdnRebase.selector, assetPrice, ignoreInterval)
        );
        require(success, "failed");
        return abi.decode(data, (bool));
    }

    function _updateEMA(uint128 secondsElapsed) internal returns (int256) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._updateEMA.selector, secondsElapsed)
        );
        require(success, "failed");
        return abi.decode(data, (int256));
    }

    function _calcBitmapIndexFromTick(int24 tick) internal returns (uint256 index_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSignature("_calcBitmapIndexFromTick(int24)", tick));
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _findHighestPopulatedTick(int24 searchStart) internal returns (int24 tick_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._findHighestPopulatedTick.selector, searchStart)
        );
        require(success, "failed");
        return abi.decode(data, (int24));
    }

    function _calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) internal returns (int24 tick_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSignature("_calcTickFromBitmapIndex(uint256,int24)", index, tickSpacing)
        );
        require(success, "failed");
        return abi.decode(data, (int24));
    }

    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal returns (uint128 leverage_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._getLeverage.selector, startPrice, liquidationPrice)
        );
        require(success, "failed");
        return abi.decode(data, (uint128));
    }

    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal returns (uint128 price_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._getLiquidationPrice.selector, startPrice, leverage)
        );
        require(success, "failed");
        return abi.decode(data, (uint128));
    }

    function _longAssetAvailable(uint128 currentPrice) internal returns (int256 available_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._longAssetAvailable.selector, currentPrice)
        );
        require(success, "failed");
        return abi.decode(data, (int256));
    }

    function _tickHash(int24 tick) internal returns (bytes32 hash_, uint256 version_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSelector(IUsdnProtocolCommon._tickHash.selector, tick));
        require(success, "failed");
        return abi.decode(data, (bytes32, uint256));
    }

    function _tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) internal returns (int256 value_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._tickValue.selector, tick, currentPrice, longTradingExpo, accumulator, tickData
            )
        );
        require(success, "failed");
        return abi.decode(data, (int256));
    }

    function _convertDepositPendingAction(DepositPendingAction memory action)
        internal
        returns (PendingAction memory pendingAction_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._convertDepositPendingAction.selector, action)
        );
        require(success, "failed");
        return abi.decode(data, (PendingAction));
    }

    function _toDepositPendingAction(PendingAction memory action)
        internal
        returns (DepositPendingAction memory vaultAction_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._toDepositPendingAction.selector, action)
        );
        require(success, "failed");
        return abi.decode(data, (DepositPendingAction));
    }

    function _toWithdrawalPendingAction(PendingAction memory action)
        internal
        returns (WithdrawalPendingAction memory vaultAction_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._toWithdrawalPendingAction.selector, action)
        );
        require(success, "failed");
        return abi.decode(data, (WithdrawalPendingAction));
    }

    function _toLongPendingAction(PendingAction memory action)
        internal
        returns (LongPendingAction memory longAction_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._toLongPendingAction.selector, action)
        );
        require(success, "failed");
        return abi.decode(data, (LongPendingAction));
    }

    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) internal returns (LiquidationsEffects memory effects_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._liquidatePositions.selector,
                currentPrice,
                iteration,
                tempLongBalance,
                tempVaultBalance
            )
        );
        require(success, "failed");
        return abi.decode(data, (LiquidationsEffects));
    }

    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        internal
        returns (bool priceUpdated_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._applyPnlAndFunding.selector, currentPrice, timestamp)
        );
        require(success, "failed");
        return abi.decode(data, (bool, int256, int256));
    }

    function _getActionablePendingAction() internal returns (PendingAction memory action_, uint128 rawIndex_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCommon._getActionablePendingAction.selector)
        );
        require(success, "failed");
        return abi.decode(data, (PendingAction, uint128));
    }

    function _positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        internal
        returns (int256 value_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._positionValue.selector, currentPrice, liqPriceWithoutPenalty, positionTotalExpo
            )
        );
        require(success, "failed");
        return abi.decode(data, (int256));
    }

    function _removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) internal {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._removeAmountFromPosition.selector,
                tick,
                index,
                pos,
                amountToRemove,
                totalExpoToRemove
            )
        );
        require(success, "failed");
    }

    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) internal returns (int256 available_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCommon._vaultAssetAvailable.selector,
                totalExpo,
                balanceVault,
                balanceLong,
                newPrice,
                oldPrice
            )
        );
        require(success, "failed");
        return abi.decode(data, (int256));
    }

    function _calcTickFromBitmapIndex(uint256 index) internal returns (int24 tick_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSignature("_calcTickFromBitmapIndex(uint256)", index));
        require(success, "failed");
        return abi.decode(data, (int24));
    }

    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) internal returns (uint256 index_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSignature("_calcBitmapIndexFromTick(int24,int24)", tick, tickSpacing)
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }
}
