// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { WusdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Functions of `WUSDN` token
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnWrap is WusdnTokenFixture {
    /**
     * @custom:scenario Wrap USDN to WUSDN and unwrap it back
     * @custom:given `toWrapAmount` is minted to a user
     * @custom:when The amount is wrapped to WUSDN
     * @custom:and The amount is unwrapped to USDN
     * @custom:then The balance of the user should be equal to the initial amount
     */
    function test_wrapAndUnwrap() public {
        uint256 toWrapAmount = usdn.balanceOf(address(this));
        require(toWrapAmount > 0, "USDN balance should be greater than 0");

        usdn.approve(address(wusdn), type(uint256).max);

        uint256 wusdnAmount = wusdn.wrap(toWrapAmount);
        uint256 usdnAmount = wusdn.unwrap(wusdnAmount);

        assertEq(wusdn.totalUsdnShares(), 0, "total USDN supply in WUSDN");
        assertEq(toWrapAmount, usdnAmount, "USDN amounts should be equal");
        assertEq(usdn.sharesOf(address(wusdn)), 0, "total WUSDN supply");
    }

    /**
     * @custom:scenario Wrap USDN to WUSDN and unwrap it back with a rebase
     * @custom:given `toWrapAmount` is minted to a user
     * @custom:when The amount is wrapped to WUSDN
     * @custom:and The amount is unwrapped to USDN
     * @custom:then The USDN shares of the user should be equal to the initial shares amount
     */
    function test_wrapAndUnwrap_rebase() public {
        uint256 toWrapAmount = usdn.balanceOf(address(this));
        require(toWrapAmount > 0, "USDN balance should be greater than 0");
        uint256 userShares = usdn.sharesOf(address(this));

        usdn.approve(address(wusdn), type(uint256).max);

        uint256 wusdnAmount = wusdn.wrap(toWrapAmount);
        usdn.rebase(usdn.MAX_DIVISOR() * 2 / 5);
        wusdn.unwrap(wusdnAmount);

        assertEq(wusdn.totalUsdnShares(), 0, "total USDN supply in WUSDN");
        assertEq(userShares, usdn.sharesOf(address(this)), "USDN shares should be equal");
        assertEq(usdn.sharesOf(address(wusdn)), 0, "total WUSDN supply");
    }
}
