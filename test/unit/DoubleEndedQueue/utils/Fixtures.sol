// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";
import { DequeHandler } from "./Handler.sol";

import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
     * @param err Assert message prefix
     */
    function _assertActionsEqual(Types.PendingAction memory a, Types.PendingAction memory b, string memory err)
        internal
        pure
    {
        assertTrue(a.action == b.action, string.concat(err, " - action type"));
        assertEq(a.timestamp, b.timestamp, string.concat(err, " - action timestamp"));
        assertEq(a.to, b.to, string.concat(err, " - action to"));
        assertEq(a.validator, b.validator, string.concat(err, " - action validator"));
        assertEq(a.securityDepositValue, b.securityDepositValue, string.concat(err, " - action security deposit"));
        assertEq(a.var1, b.var1, string.concat(err, " - action var1"));
        assertEq(a.var2, b.var2, string.concat(err, " - action var2"));
        assertEq(a.var3, b.var3, string.concat(err, " - action var3"));
        assertEq(a.var4, b.var4, string.concat(err, " - action var4"));
        assertEq(a.var5, b.var5, string.concat(err, " - action var5"));
        assertEq(a.var6, b.var6, string.concat(err, " - action var6"));
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
