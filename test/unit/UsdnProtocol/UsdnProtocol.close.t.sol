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
    uint96 private amountPosition = 500 ether;
    int24 private tick;
    uint256 private tickVersion;
    uint256 private index;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);

        bytes memory priceData = abi.encode(params.initialPrice);

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
        uint256 assetToTransfer =
            protocol.i_assetToTransfer(tick, amountPosition, userPosition.leverage, liquidationMultiplier);

        vm.expectEmit();
        emit InitiatedClosePosition(address(this), tick, tickVersion, index); // expected event
        protocol.initiateClosePosition(tick, tickVersion, index, abi.encode(uint128(2000 ether)), "");

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
    }

    /**
     * @custom:scenario The sender is not the owner of the position
     * @custom:when The user initiates a close of another user's position
     * @custom:then The protocol reverts with `UsdnProtocolUnauthorized`
     */
    function test_RevertWhen_notUser() public {
        bytes memory priceData = abi.encode(uint128(2000 ether));
        vm.prank(USER_1);
        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        protocol.initiateClosePosition(tick, tickVersion, index, priceData, "");
    }
}
