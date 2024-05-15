// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolVault } from "src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { Position, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

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
     * @param posId The unique position identifier
     * @return pos_ The position data
     * @return liquidationPenalty_ The liquidation penalty for that position (and associated tick)
     */
    function getLongPosition(PositionId calldata posId)
        external
        view
        returns (Position memory pos_, uint8 liquidationPenalty_);

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
     * @notice Get the liquidation price corresponding to a given tick number
     * @dev Uses the values from storage for the various variables
     * Note that ticks that are not a multiple of the tick spacing cannot contain a long position.
     * @param tick The tick number
     * @return The liquidation price
     */
    function getEffectivePriceForTick(int24 tick) external view returns (uint128);

    /**
     * @notice Get the liquidation price corresponding to a given tick number, taking into account the effect of funding
     * @dev Note that ticks that are not a multiple of the tick spacing cannot contain a long position.
     * @param tick The tick number
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return The liquidation price
     */
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external view returns (uint128);

    /**
     * @notice Retrieve the liquidation penalty assigned to `tick` if there are positions in it, otherwise retrieve the
     * current setting value from storage.
     * @param tick The tick number
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function getTickLiquidationPenalty(int24 tick) external view returns (uint8);
}
