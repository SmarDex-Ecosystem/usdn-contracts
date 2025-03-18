// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Vm } from "forge-std/Vm.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `rebase` function of `UsdnNoRebase`
 * @custom:background Given the current divisor is MAX_DIVISOR
 */
contract TestUsdnNoRebaseRebase is UsdnNoRebaseTokenFixture {
    uint256 internal maxDivisor;

    function setUp() public override {
        super.setUp();
        maxDivisor = usdn.MAX_DIVISOR();
        uint256 minDivisor = usdn.MIN_DIVISOR();
        assertEq(minDivisor, maxDivisor, "The max and min divisor must be equal in a no rebase setup");
        assertEq(usdn.maxTokens(), type(uint256).max, "There should not be a max amount of tokens in a no rebase setup");
    }

    /**
     * @custom:scenario Getting the divisor
     * @custom:when The `divisor` function is called
     * @custom:then The result is MAX_DIVISOR
     */
    function test_getDivisor() public view {
        assertEq(usdn.divisor(), maxDivisor);
    }

    /**
     * @custom:scenario A call to the rebase function should not do anything
     * @custom:given A user with 100 USDN
     * @custom:and This contract is the owner
     * @custom:when The `rebase` function is called
     * @custom:then No event is emitted
     * @custom:and the total supply of tokens and shares do not change
     */
    function test_rebase() public {
        usdn.mint(USER_1, 100 ether);

        uint256 totalSupplyBefore = usdn.totalSupply();
        uint256 totalSharesBefore = usdn.totalShares();
        vm.recordLogs();
        (bool rebased, uint256 oldDivisor, bytes memory callbackResult) = usdn.rebase(maxDivisor / 10);
        assertEq(vm.getRecordedLogs().length, 0, "No logs should have been emitted");

        assertFalse(rebased, "No rebase should have happened");
        assertEq(oldDivisor, maxDivisor, "divisor should not have changed");
        assertEq(callbackResult, bytes(""), "No callback should have been called");

        // supply changes
        assertEq(totalSupplyBefore, usdn.totalSupply(), "Total supply should not have changed");
        assertEq(totalSharesBefore, usdn.totalShares(), "Total shares should not have changed");
    }
}
