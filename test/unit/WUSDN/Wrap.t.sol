// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `wrap` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE and 100 USDN
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnWrap is WusdnTokenFixture {
    /**
     * @custom:scenario Wrap USDN to WUSDN
     * @custom:given `usdnAmount` is minted to a user
     * @custom:when The half (usdnAmount / 2) is deposited to WUSDN
     * @custom:then The user balance of WUSDN should be equal to the shares of USDN / MAX_DIVISOR
     */
    function test_wrap() public {
        uint256 usdnAmount = usdn.balanceOf(address(this));
        uint256 depositShares = usdn.sharesOf(address(this)) / 2;

        usdn.approve(address(wusdn), usdnAmount / 2);
        uint256 wrappedAmount = wusdn.wrap(usdnAmount / 2);

        assertEq(wusdn.totalUsdnBalance(), usdnAmount / 2, "total USDN supply in WUSDN");
        assertEq(wusdn.totalSupply(), wrappedAmount, "total WUSDN supply");
        assertEq(wusdn.balanceOf(address(this)), depositShares / usdn.MAX_DIVISOR(), "WUSDN balance");
    }
}
