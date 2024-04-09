// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `rebase` function of `USDN`
 * @custom:background Given the current divisor is MAX_DIVISOR
 */
contract TestUsdnRebase is UsdnTokenFixture {
    uint256 internal maxDivisor;
    uint256 internal minDivisor;

    function setUp() public override {
        super.setUp();
        maxDivisor = usdn.MAX_DIVISOR();
        minDivisor = usdn.MIN_DIVISOR();
    }

    /**
     * @custom:scenario Getting the divisor
     * @custom:when The `divisor` function is called
     * @custom:then The result is MAX_DIVISOR
     */
    function test_getDivisor() public {
        assertEq(usdn.divisor(), maxDivisor);
    }

    /**
     * @custom:scenario Rebase by adjusting the divisor
     * @custom:given A user with 100 USDN
     * @custom:and This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MAX_DIVISOR / 10
     * @custom:then The `Rebase` event is emitted with the old and new divisor
     * @custom:and The user's shares are unchanged
     * @custom:and The user's balance is grown proportionally (10 times)
     * @custom:and The total shares are unchanged
     * @custom:and The total supply is grown proportionally (10 times)
     */
    function test_rebase() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        usdn.mint(USER_1, 100 ether);

        vm.expectEmit();
        emit Rebase(maxDivisor, maxDivisor / 10); // expected event
        usdn.rebase(maxDivisor / 10);

        assertEq(usdn.sharesOf(USER_1), 100 ether * maxDivisor, "shares of user");
        assertEq(usdn.balanceOf(USER_1), 100 ether * 10, "balance of user");
        assertEq(usdn.totalShares(), 100 ether * maxDivisor, "total shares");
        assertEq(usdn.totalSupply(), 100 ether * 10, "total supply");
    }

    /**
     * @custom:scenario The divisor is adjusted to the same value or larger
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MAX_DIVISOR
     * @custom:or The divisor is adjusted to 2x MAX_DIVISOR
     * @custom:then The transaction does not change the divisor or rebase
     */
    function test_invalidDivisor() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        uint256 divisorBefore = usdn.divisor();

        vm.recordLogs();
        usdn.rebase(maxDivisor);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(divisorBefore, usdn.divisor(), "divisor for same divisor");
        assertEq(logs.length, 0, "logs for same divisor");

        vm.recordLogs();
        usdn.rebase(2 * maxDivisor);
        logs = vm.getRecordedLogs();

        assertEq(divisorBefore, usdn.divisor(), "divisor for larger divisor");
        assertEq(logs.length, 0, "logs for larger divisor");
    }

    /**
     * @custom:scenario The divisor is adjusted to a value that is too small
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MIN_DIVISOR - 1
     * @custom:then The transaction sets the divisor to MIN_DIVISOR
     * @custom:and Emits the Rebase event
     */
    function test_divisorTooSmallButRebase() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        vm.expectEmit();
        emit Rebase(maxDivisor, minDivisor); // expected event
        usdn.rebase(minDivisor - 1);

        assertEq(usdn.divisor(), minDivisor, "divisor");
    }

    /**
     * @custom:scenario The rebase function is called with MIN_DIVISOR - 1 but it's already MIN_DIVISOR
     * @custom:given This contract has the `REBASER_ROLE` and the divisor is MIN_DIVISOR
     * @custom:when The divisor is adjusted to MIN_DIVISOR - 1
     * @custom:then The transaction does not change the divisor or rebase
     */
    function test_divisorTooSmallButNoRebase() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.rebase(minDivisor);

        vm.recordLogs();
        usdn.rebase(minDivisor - 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(usdn.divisor(), minDivisor, "divisor");
        assertEq(logs.length, 0, "logs");
    }
}
