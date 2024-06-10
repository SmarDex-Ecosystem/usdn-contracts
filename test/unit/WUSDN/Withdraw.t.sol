// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `withdraw` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnWithdraw is WusdnTokenFixture {
    /**
     * @custom:scenario Withdraw usdn to wusdn contract
     * @custom:given 100 usdn are minted to a user
     * @custom:and 30 usdn is deposited to wusdn
     * @custom:and rebased to 0.5x MAX_DIVISOR
     * @custom:when 14 usdn are withdrawn from wusdn
     * @custom:and The total assets of usdn are 46
     * @custom:and The total supply of wusdn is 23
     */
    function test_withdraw() public {
        usdn.approve(address(wusdn), type(uint256).max);

        wusdn.wrap(30 * 10 ** usdnDecimals);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        wusdn.unwrap(14 * 10 ** usdnDecimals);

        assertEq(wusdn.totalUsdn(), (30 * 2 - 14) * 10 ** usdnDecimals, "total assets");
        assertApproxEqAbs(wusdn.totalSupply(), 23 * 10 ** usdnDecimals, 1, "total supply");
    }
}
