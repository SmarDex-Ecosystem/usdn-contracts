// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { HugeUint } from "src/libraries/HugeUint.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolCommon {
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        external
        pure
        returns (int256);

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) external pure returns (int24 tick_);

    function getEffectiveTickForPrice(uint128 price) external view returns (int24 tick_);

    function getTickLiquidationPenalty(int24 tick) external view returns (uint8 liquidationPenalty_);

    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_);

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint128 price_);

    function minTick() external view returns (int24 tick_);
}
