// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { HugeUint } from "../../libraries/HugeUint.sol";
import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol
 */
interface IUsdnProtocolLong is IUsdnProtocolTypes {
    /**
     * @notice Get the value of the lowest usable tick, taking into account the tick spacing
     * @dev Note that the effective minimum tick of a newly open long position also depends on the minimum allowed
     * leverage value and the current value of the liquidation price multiplier
     * @return The lowest usable tick
     */
    function minTick() external view returns (int24);

    /**
     * @notice Get the value of a long position when the asset price is equal to the given price, at the given timestamp
     * @dev If the current price is smaller than the liquidation price of the position without a liquidation penalty,
     * then the value of the position is negative
     * @param posId The unique position identifier
     * @param price The asset price
     * @param timestamp The timestamp of the price
     * @return The position value in assets
     */
    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256);

    /**
     * @notice Get the tick number corresponding to a given price
     * @dev Uses the values from storage for the various variables
     * @param price The price
     * @return The tick number, a multiple of the tick spacing
     */
    function getEffectiveTickForPrice(uint128 price) external view returns (int24);

    /**
     * @notice Get the tick number corresponding to a given price
     * @dev This takes into account the effects of the funding and respects the tick spacing
     * @param price The price
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @param tickSpacing The tick spacing
     * @return The tick number, a multiple of the tick spacing
     */
    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) external view returns (int24);

    /**
     * @notice Retrieve the liquidation penalty assigned to `tick` if there are positions in it, otherwise retrieve the
     * current setting value from storage
     * @param tick The tick number
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function getTickLiquidationPenalty(int24 tick) external view returns (uint24);
}
