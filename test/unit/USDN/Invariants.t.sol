// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature Invariants of `USDN`
 * @custom:background Given four users that can mint tokens to themselves, burn their balance of tokens, and transfer
 *  to other users
 */
contract TestUsdnInvariants is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();

        targetContract(address(usdn));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = usdn.rebaseTest.selector;
        selectors[1] = usdn.mintTest.selector;
        selectors[2] = usdn.burnTest.selector;
        selectors[3] = usdn.transferTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: selectors }));
    }

    /**
     * @custom:scenario Check that the contract returns the expected number of shares for each user
     */
    function invariant_shares() public displayBalancesAndShares {
        assertEq(usdn.sharesOf(USER_1), usdn.shares(USER_1), "shares of user 1");
        assertEq(usdn.sharesOf(USER_2), usdn.shares(USER_2), "shares of user 2");
        assertEq(usdn.sharesOf(USER_3), usdn.shares(USER_3), "shares of user 3");
        assertEq(usdn.sharesOf(USER_4), usdn.shares(USER_4), "shares of user 4");
    }

    /**
     * @custom:scenario Check that the contract returns the expected number of total shares
     */
    function invariant_totalShares() public displayBalancesAndShares {
        assertEq(usdn.totalShares(), usdn.totalSharesSum(), "total shares");
    }

    /**
     * @custom:scenario Check that the sum of the user shares is equal to the total shares
     */
    function invariant_sumOfSharesBalances() public displayBalancesAndShares {
        uint256 sum = usdn.shares(USER_1) + usdn.shares(USER_2) + usdn.shares(USER_3) + usdn.shares(USER_4);
        assertEq(usdn.totalShares(), sum, "sum of user shares vs total shares");
    }

    /**
     * @custom:scenario Check that the sum of all user balances is approximately equal to the total supply
     * @dev The sum of all user balances is not exactly equal to the total supply because of the rounding errors that
     * can stack up.
     */
    function invariant_totalSupply() public displayBalancesAndShares {
        uint256 sum = usdn.balanceOf(USER_1) + usdn.balanceOf(USER_2) + usdn.balanceOf(USER_3) + usdn.balanceOf(USER_4);
        assertApproxEqAbs(sum, usdn.totalSupply(), 2, "sum of user balances vs total supply");
    }

    modifier displayBalancesAndShares() {
        console2.log("USER_1 balance", usdn.balanceOf(USER_1));
        console2.log("USER_2 balance", usdn.balanceOf(USER_2));
        console2.log("USER_3 balance", usdn.balanceOf(USER_3));
        console2.log("USER_4 balance", usdn.balanceOf(USER_4));
        console2.log("USER_1 shares ", usdn.sharesOf(USER_1));
        console2.log("USER_2 shares ", usdn.sharesOf(USER_2));
        console2.log("USER_3 shares ", usdn.sharesOf(USER_3));
        console2.log("USER_4 shares ", usdn.sharesOf(USER_4));
        _;
    }

    function test() public override { }
}
