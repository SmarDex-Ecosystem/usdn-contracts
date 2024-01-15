// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { DequeHandler } from "test/unit/DoubleEndedQueue/utils/Handler.sol";

import { PendingAction } from "src/libraries/DoubleEndedQueue.sol";

/**
 * @title DequeFixture
 * @dev Utils for testing DoubleEndedQueue.sol
 */
contract DequeFixture is BaseFixture {
    DequeHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new DequeHandler();
    }

    /**
     * @dev Helper function to assert two `PendingAction` are equal.
     * Reverts if not equal.
     * @param a First `PendingAction`
     * @param b Second `PendingAction`
     */
    function _assertActionsEqual(PendingAction memory a, PendingAction memory b, string memory err) internal {
        assertTrue(a.action == b.action, string.concat(err, " - action type"));
        assertEq(a.timestamp, b.timestamp, string.concat(err, " - action timestamp"));
        assertEq(a.user, b.user, string.concat(err, " - action user"));
        assertEq(a.tick, b.tick, string.concat(err, " - action tick"));
        assertEq(a.amountOrIndex, b.amountOrIndex, string.concat(err, " - amount or index"));
        assertEq(a.assetPrice, b.assetPrice, string.concat(err, " - asset price"));
        assertEq(a.totalExpo, b.totalExpo, string.concat(err, " - total exposure"));
        assertEq(a.balanceVault, b.balanceVault, string.concat(err, " - vault balance"));
        assertEq(a.balanceLong, b.balanceLong, string.concat(err, " - long balance"));
        assertEq(a.usdnTotalSupply, b.usdnTotalSupply, string.concat(err, " - USDN total supply"));
        assertEq(a.updateTimestamp, b.updateTimestamp, string.concat(err, " - update timestamp"));
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
