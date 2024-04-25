// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ProtocolAction, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The getter functions of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium
 */
contract TestUsdnProtocolLongLong is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        params.flags.enableProtocolFees = false;
        params.initialDeposit = 4.919970269703463156 ether; // same as long trading expo
        params.flags.enableFunding = true;
        params.flags.enableProtocolFees = true;
        super._setUp(params);
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
    function test_validateAPositionAfterPriceChangedRecalculateLeverageAndTotalExpo() external {
        uint128 price = 2000 ether;
        uint128 desiredLiqPrice = 1700 ether;

        uint256 initialTotalExpo = protocol.getTotalExpo();
        TickData memory tickData = protocol.getTickData(protocol.getEffectiveTickForPrice(desiredLiqPrice));

        assertEq(tickData.totalExpo, 0, "Total expo for future tick of position should be empty");

        // Initiate a long position
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        tickData = protocol.getTickData(tick);
        (Position memory position,) = protocol.getLongPosition(tick, tickVersion, index);

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
        protocol.validateOpenPosition(abi.encode(price), EMPTY_PREVIOUS_DATA);

        uint256 previousExpo = position.totalExpo;
        // Get the updated position
        (position,) = protocol.getLongPosition(tick, tickVersion, index);
        uint256 newExpo = position.totalExpo;

        // Sanity check
        assertTrue(previousExpo != newExpo, "The expo changing is necessary for this test to work");

        // Calculate the total expo of the position after the validation
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the position's new total expo"
        );

        tickData = protocol.getTickData(tick);
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");
    }

    /**
     * @custom:scenario Call `initiateOpenPosition` reverts when the assets price
     * is lower than the minimum long price
     * @custom:given A assets price lower than the minimum long price
     * @custom:when initiateOpenPosition is called
     * @custom:then The transaction reverts with a UsdnProtocolLongPositionTooSmall error
     */
    function test_RevertWhen_openNewPositionTooLow() public {
        vm.prank(ADMIN);
        protocol.setMinLongPosition(2001 ether);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolLongPositionTooSmall.selector));
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), EMPTY_PREVIOUS_DATA, address(this));

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolLongPositionTooSmall.selector));
        protocol.initiateOpenPosition(
            2.0001 ether, 500 ether, abi.encode(1000 ether), EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    /**
     * @custom:scenario Check that the position is correctly validated when its value
     * is greater than the minimum long position value
     * @custom:given A position value greater than the minimum long position value
     * @custom:when initiateOpenPosition is called
     * @custom:then The transaction was accepted with a expected position
     */
    function test_validateOpenNewPosition() public {
        vm.prank(ADMIN);
        protocol.setMinLongPosition(1999 ether);

        uint128 desiredLiqPrice = 1000 ether;

        uint256 initialTotalExpo = protocol.getTotalExpo();
        TickData memory tickData = protocol.getTickData(protocol.getEffectiveTickForPrice(desiredLiqPrice));

        assertEq(tickData.totalExpo, 0, "Total expo for future tick of position should be empty");

        // Initiate a long position
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        tickData = protocol.getTickData(tick);
        (Position memory position,) = protocol.getLongPosition(tick, tickVersion, index);

        // Calculate the total expo of the position after the initialization
        assertEq(
            initialTotalExpo + position.totalExpo,
            protocol.getTotalExpo(),
            "Total expo should have increased by the total expo of position"
        );
        assertEq(tickData.totalExpo, position.totalExpo, "Total expo on tick is not the expected value");
    }
}
