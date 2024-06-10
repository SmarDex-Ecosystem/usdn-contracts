// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `withdraw` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnUnwrap is WusdnTokenFixture {
    /**
     * @custom:scenario Withdraw usdn to wusdn contract
     * @custom:given 100 usdn are minted to a user
     * @custom:and 30 usdn is deposited to wusdn
     * @custom:and rebased to MAX_DIVISOR / 2
     * @custom:when 14 usdn are withdrawn from wusdn
     * @custom:and The total assets of usdn are 46
     * @custom:and The total supply of wusdn is 23
     */
    function test_unwrap() public {
        uint256 depositAmount = 30 * 10 ** usdnDecimals;
        uint256 depositShares = usdn.convertToShares(depositAmount);

        usdn.approve(address(wusdn), depositAmount);

        uint256 wrappedAmount = wusdn.wrap(depositAmount);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        wusdn.unwrap(wrappedAmount / 2);

        assertEq(wusdn.totalUsdn(), usdn.convertToTokens(depositShares / 2), "total usdn supply in wusdn");
        assertEq(wusdn.totalSupply(), wrappedAmount / 2, "total wrapped supply");
    }
}
