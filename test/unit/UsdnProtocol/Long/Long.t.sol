// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The getter functions of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium
 */
contract TestUsdnProtocolLongLong is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check that the leverage and total expo of a position is re-calculated on validation
     * @custom:given An initialized position
     * @custom:when The position is validated
     * @custom:and The price fluctuated a bit
     * @custom:and Funding calculations were applied
     * @custom:then The leverage of the position should be adjusted, changing the value of the total expo for the tick
     * and the protocol
     */
    function test_validateAPositionAfterPriceChangedRecalculateLeverageAndTotalExpo() public {
        uint128 price = 2000 ether;
        uint128 desiredLiqPrice = 1700 ether;

        uint256 initialTotalExpo = protocol.getTotalExpo();
        TickData memory tickData = protocol.getTickData(protocol.getEffectiveTickForPrice(desiredLiqPrice));

        assertEq(tickData.totalExpo, 0, "Total expo for future tick of position should be empty");

        // Initiate a long position
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        tickData = protocol.getTickData(posId.tick);
        (Position memory position,) = protocol.getLongPosition(posId);

        // Calculate the total expo of the position after the initialization
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the total expo of position"
        );
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");

        _waitDelay();

        // Change the price
        price = 1999 ether;
        // Validate the position with the new price
        protocol.validateOpenPosition(payable(address(this)), abi.encode(price), EMPTY_PREVIOUS_DATA);

        uint256 previousExpo = position.totalExpo;
        // Get the updated position
        (position,) = protocol.getLongPosition(posId);
        uint256 newExpo = position.totalExpo;

        // Sanity check
        assertTrue(previousExpo != newExpo, "The expo changing is necessary for this test to work");

        // Calculate the total expo of the position after the validation
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the position's new total expo"
        );

        tickData = protocol.getTickData(posId.tick);
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");
    }

    /**
     * @custom:scenario Call `initiateOpenPosition` reverts when the position size is lower than the minimum
     * @custom:given The amount of assets lower than the minimum long position
     * @custom:when initiateOpenPosition is called
     * @custom:then The transaction reverts with a UsdnProtocolLongPositionTooSmall error
     */
    function test_RevertWhen_initiateOpenPositionAmountTooLow() public {
        uint256 minLongPositionSize = 10 ** protocol.getAssetDecimals();
        vm.prank(ADMIN);
        protocol.setMinLongPosition(minLongPositionSize);

        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolLongPositionTooSmall.selector));
        protocol.initiateOpenPosition(
            uint128(minLongPositionSize) - 1,
            1000 ether,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(this)),
            type(uint256).max,
            abi.encode(2000 ether),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Check that the position is correctly initiated when its amount of collateral
     * is greater than the minimum long position
     * @custom:given A position size greater than the minimum long position
     * @custom:when initiateOpenPosition is called
     * @custom:then The transaction was accepted with a expected position
     */
    function test_initiateOpenPositionWithEnoughAssets() public {
        vm.prank(ADMIN);
        protocol.setMinLongPosition(1 ether);

        uint128 desiredLiqPrice = 1000 ether;

        uint256 initialTotalExpo = protocol.getTotalExpo();
        TickData memory tickData = protocol.getTickData(protocol.getEffectiveTickForPrice(desiredLiqPrice));

        assertEq(tickData.totalExpo, 0, "Total expo for future tick of position should be empty");

        // Initiate a long position
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        tickData = protocol.getTickData(posId.tick);
        (Position memory position,) = protocol.getLongPosition(posId);

        // Calculate the total expo of the position after the initialization
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the total expo of position"
        );
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");
    }
}
