// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

import { Position, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @custom:feature The _saveNewPosition internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongSaveNewPosition is UsdnProtocolBaseFixture {
    uint256 internal constant LONG_AMOUNT = 1 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 10 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Test that the function save new position
     * @custom:given A validated long position
     * @custom:when The function is called with the new position
     * @custom:then The position should be created on the expected tick
     * @custom:and the protocol's state should be updated
     */
    function test_saveNewPosition() external {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);

        // state before opening the position
        uint256 balanceLongBefore = uint256(protocol.i_longAssetAvailable(CURRENT_PRICE));
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 totalExpoInTickBefore = protocol.getCurrentTotalExpoByTick(expectedTick);
        uint256 positionsInTickBefore = protocol.getCurrentPositionsInTick(expectedTick);
        uint256 totalPositionsBefore = protocol.getTotalLongPositions();

        uint128 positionTotalExpo;
        {
            bytes memory currentPriceData = abi.encode(CURRENT_PRICE);
            PriceInfo memory currentPrice =
                protocol.i_getOraclePrice(ProtocolAction.InitiateOpenPosition, block.timestamp, currentPriceData);

            // Apply fees on price
            uint128 adjustedPrice = uint128(
                (currentPrice.price + (currentPrice.price * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR())
            );

            // we calculate the closest valid tick down for the desired liq price with liquidation penalty
            int24 tick = protocol.getEffectiveTickForPrice(desiredLiqPrice);

            // remove liquidation penalty for leverage calculation
            uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
                tick - int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing()
            );

            positionTotalExpo =
                protocol.i_calculatePositionTotalExpo(uint128(LONG_AMOUNT), adjustedPrice, liqPriceWithoutPenalty);
        }
        Position memory long = Position({
            user: USER_1,
            amount: uint128(LONG_AMOUNT),
            totalExpo: positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });

        protocol.i_saveNewPosition(protocol.getEffectiveTickForPrice(desiredLiqPrice), long);

        assertEq(protocol.getBalanceLong(), balanceLongBefore + LONG_AMOUNT, "balance of long side");
        assertEq(protocol.getTotalExpo(), totalExpoBefore + positionTotalExpo, "total expo");
        assertEq(
            protocol.getCurrentTotalExpoByTick(expectedTick),
            totalExpoInTickBefore + positionTotalExpo,
            "total expo in tick"
        );
        assertEq(protocol.getPositionsInTick(expectedTick), positionsInTickBefore + 1, "positions in tick");
        assertEq(protocol.getTotalLongPositions(), totalPositionsBefore + 1, "total long positions");
    }
}
