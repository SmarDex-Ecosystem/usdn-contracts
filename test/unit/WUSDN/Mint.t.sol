// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `mint` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnMint is WusdnTokenFixture {
    /**
     * @custom:scenario Deposit usdn to wusdn contract
     * @custom:given 100 usdn are minted to a user
     * @custom:and 30 shares is minted in wusdn to a user
     * @custom:and rebased to 0.5x MAX_DIVISOR
     * @custom:when 60 shares is minted in wusdn to a user
     * @custom:and The total assets of wusdn are 18 assets
     * @custom:and The total supply of wusdn is the sum of minted shares
     */
    function test_mint() public {
        uint256 depositAmount = 30 * 10 ** usdnDecimals;
        uint256 depositShares = usdn.convertToShares(depositAmount);

        usdn.approve(address(wusdn), depositAmount * 3);

        wusdn.wrap(depositAmount);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);

        depositShares += usdn.convertToShares(depositAmount * 2);
        wusdn.wrap(depositAmount * 2);

        assertEq(wusdn.totalUsdn(), usdn.convertToTokens(depositShares), "total USDN supply in WUSDN");
        assertEq(wusdn.totalSupply(), depositAmount * 2, "total WUSDN supply");
    }
}
