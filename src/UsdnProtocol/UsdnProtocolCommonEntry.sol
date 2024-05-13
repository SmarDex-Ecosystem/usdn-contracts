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

abstract contract UsdnProtocolCommonEntry is
    UsdnProtocolBaseStorage,
    IUsdnProtocolCommon,
    InitializableReentrancyGuard
{
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
}
