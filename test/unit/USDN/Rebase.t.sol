// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Vm } from "forge-std/Vm.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";
import { RebaseHandler } from "./utils/RebaseHandler.sol";

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
    function test_getDivisor() public view {
        assertEq(usdn.divisor(), maxDivisor);
    }

    /**
     * @custom:scenario Rebase by adjusting the divisor
     * @custom:given A user with 100 USDN
     * @custom:and This contract has the `REBASER_ROLE`
     * @custom:and No rebase handler is defined
     * @custom:when The divisor is adjusted to MAX_DIVISOR / 10
     * @custom:then The `Rebase` event is emitted with the old and new divisor
     * @custom:and The rebased boolean is true
     * @custom:and The old divisor value is returned
     * @custom:and No callback result is returned
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
        (bool rebased, uint256 oldDivisor, bytes memory callbackResult) = usdn.rebase(maxDivisor / 10);

        assertTrue(rebased, "rebased bool");
        assertEq(oldDivisor, maxDivisor, "old divisor");
        assertEq(callbackResult, "", "callback result");
        assertEq(usdn.sharesOf(USER_1), 100 ether * maxDivisor, "shares of user");
        assertEq(usdn.balanceOf(USER_1), 100 ether * 10, "balance of user");
        assertEq(usdn.totalShares(), 100 ether * maxDivisor, "total shares");
        assertEq(usdn.totalSupply(), 100 ether * 10, "total supply");
    }

    /**
     * @custom:scenario Rebase when a rebase handler is set
     * @custom:given A rebase handler contract that returns the abi-encoded callback arguments and emits `TestCallBack`
     * @custom:when The `rebase` function of USDN is called with a new divisor
     * @custom:then The rebase handler is called with the old and new divisor values
     * @custom:and The handler's return value is forwarded to the caller
     */
    function test_rebaseWithCallback() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        RebaseHandler handler = new RebaseHandler();
        usdn.setRebaseHandler(handler);

        vm.expectEmit(address(handler));
        emit TestCallback();
        (bool rebased,, bytes memory callbackResult) = usdn.rebase(maxDivisor / 10);
        (uint256 oldDivisor, uint256 newDivisor) = abi.decode(callbackResult, (uint256, uint256));

        assertTrue(rebased, "rebased bool");
        assertEq(oldDivisor, maxDivisor, "old divisor");
        assertEq(newDivisor, maxDivisor / 10, "new divisor");
    }

    /**
     * @custom:scenario The divisor is adjusted to the same value or larger
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MAX_DIVISOR
     * @custom:or The divisor is adjusted to 2x MAX_DIVISOR
     * @custom:then The transaction does not change the divisor or rebase
     * @custom:and The rebased boolean is false
     * @custom:and The unchanged divisor value is returned
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
        (bool rebased, uint256 oldDivisor,) = usdn.rebase(2 * maxDivisor);
        logs = vm.getRecordedLogs();

        assertEq(rebased, false, "rebased bool");
        assertEq(oldDivisor, divisorBefore, "old divisor");
        assertEq(divisorBefore, usdn.divisor(), "divisor for larger divisor");
        assertEq(logs.length, 0, "logs for larger divisor");
    }

    /**
     * @custom:scenario The divisor is adjusted to a value that is too small
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MIN_DIVISOR - 1
     * @custom:then The transaction sets the divisor to MIN_DIVISOR
     * @custom:and Emits the Rebase event
     * @custom:and The rebased boolean is true
     * @custom:and The old divisor value is returned
     */
    function test_divisorTooSmallButRebase() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        vm.expectEmit();
        emit Rebase(maxDivisor, minDivisor); // expected event
        (bool rebased, uint256 oldDivisor,) = usdn.rebase(minDivisor - 1);

        assertTrue(rebased, "rebased bool");
        assertEq(oldDivisor, maxDivisor, "old divisor");
        assertEq(usdn.divisor(), minDivisor, "new divisor");
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
        (bool rebased, uint256 oldDivisor,) = usdn.rebase(minDivisor - 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(rebased, false, "rebased bool");
        assertEq(oldDivisor, minDivisor, "old divisor");
        assertEq(usdn.divisor(), minDivisor, "new divisor");
        assertEq(logs.length, 0, "logs");
    }
}
