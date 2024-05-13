// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { HugeUint } from "src/libraries/HugeUint.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolCommon {
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        external
        returns (int256);

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) external returns (int24 tick_);

    function getEffectiveTickForPrice(uint128 price) external returns (int24 tick_);

    function getTickLiquidationPenalty(int24 tick) external returns (uint8 liquidationPenalty_);

    function getEffectivePriceForTick(int24 tick) external returns (uint128 price_);

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external returns (uint128 price_);

    function minTick() external returns (int24 tick_);

    function _getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        external
        returns (PriceInfo memory price_);
}
