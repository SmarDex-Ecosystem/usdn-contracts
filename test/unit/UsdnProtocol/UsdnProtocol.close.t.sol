// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {
    ProtocolAction,
    LongPendingAction,
    PendingAction,
    Position
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 100_000 wstETH in their wallet
 * @custom:and A position with 500 wstETH in collateral
 */
contract TestUsdnProtocolClose is UsdnProtocolBaseFixture {
    uint96 private amountPosition = 1 ether;
    int24 private tick;
    uint256 private tickVersion;
    uint256 private index;
    bytes private priceData;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);

        priceData = abi.encode(params.initialPrice);

        (tick, tickVersion, index) =
            protocol.initiateOpenPosition(amountPosition, params.initialPrice / 2, priceData, "");
        protocol.validateOpenPosition(priceData, "");
    }

    /**
     * @custom:scenario The user initiates a close position action
     * @custom:given The user already have a position with 500 wstETH and a desired liquidation price of 1000$
     * @custom:when The user initiate the close of the position
     * @custom:then The protocol initiate the closure of the position and emits the InitiatedClosePosition event
     * @custom:and the state changes are as expected
     */
    function test_initiateClosePosition() public {
        Position memory userPosition = protocol.getLongPosition(tick, tickVersion, index);
        uint256 liquidationMultiplier = protocol.getLiquidationMultiplier();
        uint256 balanceLongBefore = protocol.getBalanceLong();
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 totalExpoByTickBefore = protocol.getTotalExpoByTick(tick, tickVersion);
        uint256 longPositionLengthBefore = protocol.getLongPositionsLength(tick);
        uint256 totalLongPositionBefore = protocol.getTotalLongPositions();
        uint256 assetToTransfer =
            protocol.i_assetToTransfer(tick, amountPosition, userPosition.leverage, liquidationMultiplier);

        vm.expectEmit();
        emit InitiatedClosePosition(address(this), tick, tickVersion, index); // expected event
        protocol.initiateClosePosition(tick, tickVersion, index, priceData, "");

        // the pending action should not yet be actionable by a third party
        vm.startPrank(address(0)); // simulate front-end calls by someone else
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getActionablePendingAction(0));
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.action == ProtocolAction.ValidateClosePosition, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.tick, tick, "action tick");
        assertEq(action.closeAmount, amountPosition, "action closeAmount");
        assertEq(action.closeLeverage, userPosition.leverage, "action closeLeverage");
        assertEq(action.tickVersion, tickVersion, "action tickVersion");
        assertEq(action.index, index, "action index");
        assertEq(action.closeLiqMultiplier, liquidationMultiplier, "action closeLiqMultiplier");
        assertEq(action.closeTempTransfer, assetToTransfer, "action closeTempTransfer");

        //check balance long after
        uint256 balanceLongAfter = protocol.getBalanceLong();
        assertEq(balanceLongAfter, balanceLongBefore - assetToTransfer, "wrong balance long after");
        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        action = protocol.i_toLongPendingAction(protocol.getActionablePendingAction(0));
        assertEq(action.user, address(this), "pending action user");
        vm.stopPrank();

        uint256 totalExpoAfter = protocol.getTotalExpo();
        uint256 totalExpoByTickAfter = protocol.getTotalExpoByTick(tick, tickVersion);
        uint256 longPositionLengthAfter = protocol.getLongPositionsLength(tick);
        uint256 totalLongPositionAfter = protocol.getTotalLongPositions();
        assertLt(totalExpoAfter, totalExpoBefore, "wrong total exposure after");
        assertLt(totalExpoByTickAfter, totalExpoByTickBefore, "wrong total exposure by tick after");
        assertEq(longPositionLengthBefore - 1, longPositionLengthAfter, "wrong long position length after");
        assertEq(totalLongPositionBefore - 1, totalLongPositionAfter, "wrong total long position after");
    }

    /**
     * @custom:scenario The sender is not the owner of the position
     * @custom:when The user initiates a close of another user's position
     * @custom:then The protocol reverts with `UsdnProtocolUnauthorized`
     */
    function test_RevertWhen_notUser() public {
        vm.prank(USER_1);
        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.initiateClosePosition(tick, tickVersion, index, priceData, "");
    }

    /**
     * @custom:scenario The user validates a close position action
     * @custom:given The user already have a position with 500 wstETH and initiated the close of the position
     * @custom:when The user validate the close of the position
     * @custom:then The protocol initiate the closure of the position and emits the ValidatedClosePosition event
     */
    function test_validateClosePosition() public {
        bytes memory newPrice = abi.encode(params.initialPrice + 500 ether);
        protocol.initiateClosePosition(tick, tickVersion, index, newPrice, "");
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        uint256 liquidationMultiplier = protocol.getLiquidationMultiplier();
        uint256 amountToTransfer =
            protocol.i_assetToTransfer(tick, amountPosition, action.closeLeverage, liquidationMultiplier);

        vm.expectEmit();
        emit ValidatedClosePosition(
            address(this),
            tick,
            tickVersion,
            index,
            amountToTransfer,
            int256(amountToTransfer) - int256(uint256(amountPosition))
        );
        protocol.validateClosePosition(newPrice, "");
    }
}
