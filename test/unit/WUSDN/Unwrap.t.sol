// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `unwrap` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE and 100 USDN
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnUnwrap is WusdnTokenFixture {
    /**
     * @custom:scenario Unwrap WUSDN to USDN
     * @custom:given `usdnAmount` is minted to a user
     * @custom:and The half (usdnAmount / 2) is deposited to WUSDN
     * @custom:when The half (wusdnAmount / 2) is withdrawn from WUSDN
     * @custom:then The user sould have usdnAmount * 3 / 4 USDN
     * @custom:and wusdnAmount / 2 WUSDN
     */
    function test_unwrap() public {
        uint256 usdnAmount = usdn.balanceOf(address(this));

        usdn.approve(address(wusdn), usdnAmount / 2);
        uint256 wrappedAmount = wusdn.wrap(usdnAmount / 2);
        wusdn.unwrap(wrappedAmount / 2);

        assertEq(wusdn.totalUsdnBalance(), usdnAmount / 4, "total usdn supply in wusdn");
        assertEq(wusdn.totalSupply(), wrappedAmount / 2, "total wrapped supply");
        assertEq(usdn.balanceOf(address(this)), usdnAmount * 3 / 4, "usdn balance");
        assertEq(wusdn.balanceOf(address(this)), wrappedAmount / 2, "wusdn balance");
    }
}
