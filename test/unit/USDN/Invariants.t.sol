// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console2 } from "forge-std/Test.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Invariants of `USDN`
 * @custom:background Given four users that can mint tokens to themselves, burn their balance of tokens, and transfer
 *  to other users
 */
contract TestUsdnInvariants is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();

        targetContract(address(usdn));
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = usdn.rebaseTest.selector;
        selectors[1] = usdn.mintTest.selector;
        selectors[2] = usdn.burnTest.selector;
        selectors[3] = usdn.transferTest.selector;
        selectors[4] = usdn.mintSharesTest.selector;
        selectors[5] = usdn.burnSharesTest.selector;
        selectors[6] = usdn.transferSharesTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: selectors }));
        targetSender(USER_1);
        targetSender(USER_2);
        targetSender(USER_3);
        targetSender(USER_4);
    }

    /**
     * @custom:scenario Check that the contract returns the expected number of shares for each user
     */
    function invariant_shares() public view displayBalancesAndShares {
        assertEq(usdn.sharesOf(USER_1), usdn.getSharesOfAddress(USER_1), "shares of user 1");
        assertEq(usdn.sharesOf(USER_2), usdn.getSharesOfAddress(USER_2), "shares of user 2");
        assertEq(usdn.sharesOf(USER_3), usdn.getSharesOfAddress(USER_3), "shares of user 3");
        assertEq(usdn.sharesOf(USER_4), usdn.getSharesOfAddress(USER_4), "shares of user 4");
    }

    /**
     * @custom:scenario Check that the contract returns the expected number of total shares
     */
    function invariant_totalShares() public view displayBalancesAndShares {
        assertEq(usdn.totalShares(), usdn.totalSharesSum(), "total shares");
    }

    /**
     * @custom:scenario Check that the sum of the user shares is equal to the total shares
     */
    function invariant_sumOfSharesBalances() public view displayBalancesAndShares {
        uint256 sum;
        for (uint256 i = 0; i < usdn.getLengthOfShares(); i++) {
            (, uint256 value) = usdn.getElementOfIndex(i);
            sum += value;
        }
        assertEq(usdn.totalShares(), sum, "sum of user shares vs total shares");
    }

    /**
     * @custom:scenario Check that the sum of all user balances is approximately equal to the total supply
     * @dev The sum of all user balances is not exactly equal to the total supply because of the rounding errors that
     * can stack up.
     */
    function invariant_totalSupply() public view displayBalancesAndShares {
        uint256 sum;
        for (uint256 i = 0; i < usdn.getLengthOfShares(); i++) {
            (address user,) = usdn.getElementOfIndex(i);
            sum += usdn.balanceOf(user);
        }
        assertApproxEqAbs(sum, usdn.totalSupply(), usdn.getLengthOfShares(), "sum of user balances vs total supply");
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
}
