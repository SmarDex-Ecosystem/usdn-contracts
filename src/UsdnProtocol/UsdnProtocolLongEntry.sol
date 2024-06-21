// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IUsdnProtocolLong } from "../interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolLongLibrary as longLib } from "./libraries/UsdnProtocolLongLibrary.sol";

abstract contract UsdnProtocolLongEntry is UsdnProtocolStorage, IUsdnProtocolLong {
    /// @inheritdoc IUsdnProtocolLong
    function minTick() external view returns (int24 tick_) {
        return longLib.minTick(s);
    }

    /// @inheritdoc IUsdnProtocolLong
    function maxTick() external view returns (int24 tick_) {
        return longLib.maxTick(s);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getLongPosition(PositionId memory posId)
        external
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        return longLib.getLongPosition(s, posId);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getMinLiquidationPrice(uint128 price) external view returns (uint128 liquidationPrice_) {
        return longLib.getMinLiquidationPrice(s, price);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        return longLib.getPositionValue(s, posId, price, timestamp);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price) external view returns (int24 tick_) {
        return longLib.getEffectiveTickForPrice(s, price);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) external pure returns (int24 tick_) {
        return longLib.getEffectiveTickForPrice(price, assetPrice, longTradingExpo, accumulator, tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_) {
        return longLib.getEffectivePriceForTick(s, tick);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint128 price_) {
        return longLib.getEffectivePriceForTick(tick, assetPrice, longTradingExpo, accumulator);
    }

    /// @inheritdoc IUsdnProtocolLong
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 available_)
    {
        return longLib.longAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolLong
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256 expo_) {
        return longLib.longTradingExpoWithFunding(s, currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getTickLiquidationPenalty(int24 tick) external view returns (uint8 liquidationPenalty_) {
        return longLib.getTickLiquidationPenalty(s, tick);
    }
}
