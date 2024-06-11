// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature Functions of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnWrap is WusdnTokenFixture {
    function test_wrapAndUnwrap() public {
        uint256 toWrapAmount = 30 * 10 ** usdnDecimals;

        usdn.approve(address(wusdn), type(uint256).max);

        uint256 wusdnAmount = wusdn.wrap(toWrapAmount);
        uint256 usdnAmount = wusdn.unwrap(wusdnAmount);

        assertEq(wusdn.totalUsdn(), 0, "total USDN supply in WUSDN");
        assertEq(toWrapAmount, usdnAmount, "USDN amounts should be equal");
        assertEq(usdn.sharesOf(address(wusdn)), 0, "total WUSDN supply");
    }
}
