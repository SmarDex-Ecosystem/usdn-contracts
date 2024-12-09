// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { HugeUint } from "../../libraries/HugeUint.sol";
import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolLong is IUsdnProtocolTypes {
    /**
     * @notice Gets the value of the lowest usable tick, taking into account the tick spacing.
     * @dev Note that the effective minimum tick of a newly open long position also depends on the minimum allowed
     * leverage value and the current value of the liquidation price multiplier.
     * @return tick_ The lowest usable tick.
     */
    function minTick() external view returns (int24 tick_);

    /**
     * @notice Gets the liquidation price from a desired one by taking into account the tick rounding.
     * @param desiredLiqPriceWithoutPenalty The desired liquidation price without the penalty.
     * @param assetPrice The current price of the asset.
     * @param longTradingExpo The trading exposition of the long side.
     * @param accumulator The liquidation multiplier accumulator.
     * @param tickSpacing The tick spacing.
     * @param liquidationPenalty The liquidation penalty set on the tick.
     * @return liqPrice_ The new liquidation price without the penalty.
     */
    function getLiqPriceFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external view returns (uint128 liqPrice_);

    /**
     * @notice Gets the value of a long position when the asset price is equal to the given price, at the given
     * timestamp.
     * @dev If the current price is smaller than the liquidation price of the position without the liquidation penalty,
     * then the value of the position is negative.
     * @param posId The unique position identifier.
     * @param price The asset price.
     * @param timestamp The timestamp of the price.
     * @return value_ The position value in assets.
     */
    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_);

    /**
     * @notice Gets the tick number corresponding to a given price, accounting for funding effects.
     * @dev Uses the stored parameters for calculation.
     * @param price The asset price.
     * @return tick_ The tick number, a multiple of the tick spacing.
     */
    function getEffectiveTickForPrice(uint128 price) external view returns (int24 tick_);

    /**
     * @notice Gets the tick number corresponding to a given price, accounting for funding effects.
     * @param price The asset price.
     * @param assetPrice The current price of the asset.
     * @param longTradingExpo The trading exposition of the long side.
     * @param accumulator The liquidation multiplier accumulator.
     * @param tickSpacing The tick spacing.
     * @return tick_ The tick number, a multiple of the tick spacing.
     */
    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) external view returns (int24 tick_);

    /**
     * @notice Retrieves the liquidation penalty assigned to the given tick if there are positions in it, otherwise
     * retrieve the current setting value from storage.
     * @param tick The tick number.
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units.
     */
    function getTickLiquidationPenalty(int24 tick) external view returns (uint24 liquidationPenalty_);

    /**
     * @notice Gets a long position identified by its tick, tick version and index.
     * @param posId The unique position identifier.
     * @return pos_ The position data.
     * @return liquidationPenalty_ The liquidation penalty for that position.
     */
    function getLongPosition(PositionId calldata posId)
        external
        view
        returns (Position memory pos_, uint24 liquidationPenalty_);

    /**
     * @notice Gets the predicted value of the long balance for the given asset price and timestamp.
     * @dev The effects of the funding and any PnL of the long positions since the last contract state
     * update is taken into account, as well as the fees. If the provided timestamp is older than the last state
     * update, the function reverts with `UsdnProtocolTimestampTooOld`. The value cannot be below 0.
     * @param currentPrice The given asset price.
     * @param timestamp The timestamp corresponding to the given price.
     * @return available_ The long balance value in assets.
     */
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (uint256 available_);

    /**
     * @notice Gets the predicted value of the long trading exposure for the given asset price and timestamp.
     * @dev The effects of the funding and any profit or loss of the long positions since the last contract state
     * update is taken into account. If the provided timestamp is older than the last state update, the function reverts
     * with `UsdnProtocolTimestampTooOld`. The value cannot be below 0.
     * @param currentPrice The given asset price.
     * @param timestamp The timestamp corresponding to the given price.
     * @return expo_ The long trading exposure value in assets.
     */
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (uint256 expo_);
}
