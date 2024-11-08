// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IUsdnProtocolLong } from "../interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { UsdnProtocolLongLibrary as Long } from "./libraries/UsdnProtocolLongLibrary.sol";

abstract contract UsdnProtocolLong is IUsdnProtocolLong {
    /// @inheritdoc IUsdnProtocolLong
    function minTick() external view returns (int24 tick_) {
        return Long.minTick();
    }

    function getLiqPriceFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (uint128 liqPrice_) {
        (, liqPrice_) = Long._getTickFromDesiredLiqPrice(
            desiredLiqPriceWithoutPenalty, assetPrice, longTradingExpo, accumulator, tickSpacing, liquidationPenalty
        );
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        return Long.getPositionValue(posId, price, timestamp);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price) external view returns (int24 tick_) {
        return Long.getEffectiveTickForPrice(price);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) external pure returns (int24 tick_) {
        return Long.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getTickLiquidationPenalty(int24 tick) external view returns (uint24 liquidationPenalty_) {
        return Long.getTickLiquidationPenalty(tick);
    }
}
