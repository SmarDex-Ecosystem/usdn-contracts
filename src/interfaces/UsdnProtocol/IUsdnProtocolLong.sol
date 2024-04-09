// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolVault } from "src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolLong is IUsdnProtocolVault {
    /**
     * @notice Get the value of the lowest usable tick, taking into account the tick spacing
     * @dev Note that the effective minimum tick of a newly open long position also depends on the minimum allowed
     * leverage value and the current value of the liquidation price multiplier.
     */
    function minTick() external view returns (int24);

    /**
     * @notice Get the value of the highest usable tick, taking into account the tick spacing
     * @dev Note that the effective maximum tick of a newly open long position also depends on the maximum allowed
     * leverage value and the current value of the liquidation price multiplier.
     */
    function maxTick() external view returns (int24);

    /**
     * @notice Get a long position identified by its tick, tickVersion and index
     * @param tick The tick containing the long position
     * @param tickVersion The tick version
     * @param index The index of the long position inside the tick array
     * @return The position data
     * @return The liquidation penalty for that position (and associated tick)
     */
    function getLongPosition(int24 tick, uint256 tickVersion, uint256 index)
        external
        view
        returns (Position memory, uint8);

    /**
     * @notice Get the minimum acceptable desired liquidation price for a new long position
     * @dev This takes into account the current value of the liquidation price multiplier and the minimum leverage value
     * @param price The current asset price
     */
    function getMinLiquidationPrice(uint128 price) external view returns (uint128);

    /**
     * @notice Get the value of a long position when the asset price is equal to the given price, at the given timestamp
     * @dev If the current price is smaller than the liquidation price of the position without liquidation penalty,
     * then the value of the position is negative.
     * @param tick The tick containing the long position
     * @param tickVersion The tick version
     * @param index The index of the long position inside the tick array
     * @param price The asset price
     * @param timestamp The timestamp of the price
     */
    function getPositionValue(int24 tick, uint256 tickVersion, uint256 index, uint128 price, uint128 timestamp)
        external
        view
        returns (int256);

    /**
     * @notice Get the tick number corresponding to a given price
     * @dev This takes into account the liquidation price multiplier and the tick spacing
     * @param price The price
     */
    function getEffectiveTickForPrice(uint128 price) external view returns (int24);

    /**
     * @notice Get the tick number corresponding to a given price
     * @dev This takes into account the liquidation price multiplier and the tick spacing
     * @param price The price
     * @param liqMultiplier The liquidation price multiplier
     */
    function getEffectiveTickForPrice(uint128 price, uint256 liqMultiplier) external view returns (int24);

    /**
     * @notice Get the liquidation price corresponding to a given tick number
     * @dev This takes into account the liquidation price multiplier.
     * Note that ticks that are not a multiple of the tick spacing cannot contain a long position.
     * @param tick The tick number
     */
    function getEffectivePriceForTick(int24 tick) external view returns (uint128);

    /**
     * @notice Get the liquidation price corresponding to a given tick number
     * @dev This takes into account the liquidation price multiplier.
     * Note that ticks that are not a multiple of the tick spacing cannot contain a long position.
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier
     */
    function getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) external view returns (uint128);
}
