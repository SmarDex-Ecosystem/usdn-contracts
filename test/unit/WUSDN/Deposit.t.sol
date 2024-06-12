// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `deposit` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnDeposit is WusdnTokenFixture {
    /**
     * @custom:scenario Deposit usdn to wusdn contract
     * @custom:given 100 usdn are minted to a user
     * @custom:and 30 usdn is deposited to wusdn
     * @custom:and rebased to 0.5x MAX_DIVISOR
     * @custom:when 70 usdn are deposited to wusdn
     * @custom:and The total assets of wusdn are 130
     * @custom:and The total supply of wusdn is 65
     */
    function test_deposit() public {
        usdn.approve(address(wusdn), type(uint256).max);

        wusdn.deposit(30 * 10 ** usdnDecimals, address(this));
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        wusdn.deposit(70 * 10 ** usdnDecimals, address(this));

        assertEq(wusdn.totalAssets(), 130 * 10 ** usdnDecimals, "total assets");
        assertEq(wusdn.totalSupply(), 65 * 10 ** usdnDecimals, "total supply");
    }
}
