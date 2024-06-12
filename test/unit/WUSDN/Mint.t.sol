// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

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
        usdn.approve(address(wusdn), type(uint256).max);

        uint256 shares1 = 30 ether;
        wusdn.mint(shares1, address(this));
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        uint256 shares2 = 60 ether;
        wusdn.mint(shares2, address(this));
        assertApproxEqAbs(wusdn.totalAssets(), wusdn.convertToAssets(shares1 + shares2), 1, "total assets");
        assertEq(wusdn.totalSupply(), shares1 + shares2, "total supply");
    }
}
