// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IUsdnProtocolLong } from "../interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolLongLibrary as Long } from "./libraries/UsdnProtocolLongLibrary.sol";

abstract contract UsdnProtocolLong is UsdnProtocolStorage, IUsdnProtocolLong {
    /// @inheritdoc IUsdnProtocolLong
    function minTick() external view returns (int24 tick_) {
        return Long.minTick(s);
    }

    /// @inheritdoc IUsdnProtocolLong
    function maxTick() external view returns (int24 tick_) {
        return Long.maxTick(s);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getLongPosition(PositionId memory posId)
        external
        view
        returns (Position memory pos_, uint24 liquidationPenalty_)
    {
        return Long.getLongPosition(s, posId);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        return Long.getPositionValue(s, posId, price, timestamp);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price) external view returns (int24 tick_) {
        return Long.getEffectiveTickForPrice(s, price);
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
    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_) {
        return Long.getEffectivePriceForTick(s, tick);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint128 price_) {
        return Long.getEffectivePriceForTick(tick, assetPrice, longTradingExpo, accumulator);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getTickLiquidationPenalty(int24 tick) external view returns (uint24 liquidationPenalty_) {
        return Long.getTickLiquidationPenalty(s, tick);
    }
}
