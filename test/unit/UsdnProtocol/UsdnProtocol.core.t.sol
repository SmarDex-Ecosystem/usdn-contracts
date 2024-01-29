// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1, USER_2, USER_3 } from "test/utils/Constants.sol";

import { Position, PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @custom:feature The functions of the core of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolCore is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check return values of the `funding` function
     * @custom:when The timestamp is the same as the initial timestamp
     * @custom:then The funding should be 0
     */
    function test_funding() public {
        (int256 fund, int256 longExpo, int256 vaultExpo) =
            protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp));
        assertEq(fund, 0, "funding should be 0 if no time has passed");
        assertEq(longExpo, 4.919970269703462172 ether, "longExpo if no time has passed");
        assertEq(vaultExpo, 10 ether, "vaultExpo if no time has passed");
    }

    /**
     * @custom:scenario Calling the `funding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_funding_pastTimestamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp) - 1);
    }

    /**
     * @custom:scenario The sum of all long position's value is equal to the long side available balance
     * @custom:given No time has elapsed since the initialization
     * @custom:and The price of the asset is equal to the initial price
     * @custom:when The sum of all position values is calculated
     * @custom:then The long side available balance is equal to the sum of all position values
     * @dev Due to imprecision in the calculations, there are in practice a few wei of difference, but always in favor
     * of the protocol (see fuzzing tests)
     */
    function test_longAssetAvailable() public {
        // calculate the value of the init position
        uint128 initLiqPrice = protocol.getEffectivePriceForTick(protocol.minTick());
        uint256 initPosValue = protocol.positionValue(
            DEFAULT_PARAMS.initialPrice, initLiqPrice, protocol.FIRST_LONG_AMOUNT(), defaultPosLeverage
        );

        // calculate the value of the deployer's long position
        uint128 longLiqPrice =
            protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(DEFAULT_PARAMS.initialPrice / 2));
        uint256 longPosValue = protocol.positionValue(
            DEFAULT_PARAMS.initialPrice,
            longLiqPrice,
            DEFAULT_PARAMS.initialLong - protocol.FIRST_LONG_AMOUNT(),
            initialLongLeverage
        );

        // calculate the sum to know the theoretical long balance
        uint256 sumOfPositions = longPosValue + initPosValue;

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(uint256(protocol.longAssetAvailable(DEFAULT_PARAMS.initialPrice)), sumOfPositions, "long balance");
    }

    /**
     * @custom:scenario Get the first actionable pending action
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The first actionable pending action is requested
     * @custom:then The pending action is returned
     */
    function test_getActionablePendingAction() public {
        wstETH.mint(address(this), 100_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);
        // there should be no pending action at this stage
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "pending action before initiate");
        // initiate long
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        // the pending action is not yet actionable
        action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "pending action after initiate");
        // the pending action is actionable after the validation deadline
        skip(protocol.validationDeadline() + 1);
        action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(this), "action user");
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is sparse
     * @custom:given 3 users have initiated a deposit
     * @custom:and The first and second pending actions have been manually removed from the queue
     * @custom:when The first actionable pending action is requested with a max iter of 1
     * @custom:or The first actionable pending action is requested with a max iter of 2
     * @custom:then No actionable pending action is returned with a max iter of 1
     * @custom:or The third pending action is returned with a max iter of 2
     */
    function test_getActionablePendingActionSparse() public {
        wstETH.mint(USER_1, 100_000 ether);
        wstETH.mint(USER_2, 100_000 ether);
        wstETH.mint(USER_3, 100_000 ether);
        // Setup 3 pending actions
        vm.startPrank(USER_1);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        vm.stopPrank();
        vm.startPrank(USER_2);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        vm.stopPrank();
        vm.startPrank(USER_3);
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(2000 ether), "");
        vm.stopPrank();

        // Simulate the second item in the queue being empty (sets it to zero values)
        protocol.removePendingAction(1, USER_2);
        // Simulate the first item in the queue being empty
        // This will pop the first item, but leave the second empty
        protocol.removePendingAction(0, USER_1);

        // Wait
        skip(protocol.validationDeadline() + 1);

        // With 1 max iter, we should not get any pending action (since the first item in the queue is zeroed)
        PendingAction memory action = protocol.getActionablePendingAction(1);
        assertEq(action.user, address(0), "max iter 1");
        // With 2 max iter, we should get the action corresponding to the third user, which is actionable
        action = protocol.getActionablePendingAction(2);
        assertTrue(action.user == USER_3, "max iter 2");
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is empty
     * @custom:given The queue is empty
     * @custom:when The first actionable pending action is requested
     * @custom:then No actionable pending action is returned
     */
    function test_getActionablePendingActionEmpty() public {
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(0));
    }
}
