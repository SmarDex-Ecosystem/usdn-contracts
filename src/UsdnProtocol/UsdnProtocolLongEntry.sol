// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { HugeUint } from "../libraries/HugeUint.sol";
import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { Position, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolLongLibrary as lib } from "./UsdnProtocolLongLibrary.sol";

abstract contract UsdnProtocolLongEntry is UsdnProtocolBaseStorage {
    function minTick() public view returns (int24 tick_) {
        return lib.minTick(s);
    }

    function maxTick() external view returns (int24 tick_) {
        return lib.maxTick(s);
    }

    function getLongPosition(PositionId memory posId)
        public
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        return lib.getLongPosition(s, posId);
    }

    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) external view returns (uint128 liquidationPrice_) {
        return lib.getMinLiquidationPrice(s, price);
    }

    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        return lib.getPositionValue(s, posId, price, timestamp);
    }

    function getEffectiveTickForPrice(uint128 price) public view returns (int24 tick_) {
        return lib.getEffectiveTickForPrice(s, price);
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

    function getEffectivePriceForTick(int24 tick) public view returns (uint128 price_) {
        return lib.getEffectivePriceForTick(s, tick);
    }

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        return lib.getEffectivePriceForTick(tick, assetPrice, longTradingExpo, accumulator);
    }

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        return lib.longAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public view returns (int256 expo_) {
        return lib.longTradingExpoWithFunding(s, currentPrice, timestamp);
    }

    // / @inheritdoc IUsdnProtocolLong
    function getTickLiquidationPenalty(int24 tick) public view returns (uint8 liquidationPenalty_) {
        return lib.getTickLiquidationPenalty(s, tick);
    }
}
