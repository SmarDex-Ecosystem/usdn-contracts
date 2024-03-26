// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `mint` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnMint is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
    }

    /**
     * @custom:scenario Deposit usdn to wusdn contract
     * @custom:given 100 usdn are minted to a user
     * @custom:and 30 shares is minted in wusdn to a user
     * @custom:and rebased to 0.5x MAX_DIVISOR
     * @custom:when 70 shares is minted in wusdn to a user
     * @custom:and The total assets of wusdn are 18 assets
     * @custom:and The total supply of wusdn is 90
     */
    function test_mint() public {
        usdn.approve(address(wusdn), type(uint256).max);

        wusdn.mint(30 * 10 ** usdnDecimals, address(this));
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        wusdn.mint(60 * 10 ** usdnDecimals, address(this));

        assertApproxEqAbs(wusdn.totalAssets(), wusdn.convertToAssets(90 * 10 ** usdnDecimals), 1, "total assets");
        assertEq(wusdn.totalSupply(), 90 * 10 ** usdnDecimals, "total supply");
    }
}
