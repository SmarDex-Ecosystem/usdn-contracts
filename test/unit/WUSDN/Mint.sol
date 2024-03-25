// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
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
     * @custom:and 30 usdn of share is deposited to wusdn
     * @custom:and rebased to 0.5x MAX_DIVISOR
     * @custom:when 70 usdn of share is deposited to wusdn
     * @custom:and The total assets of wusdn are wusdn.convertToAssets(90 usdn)
     * @custom:and The total supply of wusdn is 90
     */
    function test_mint() public {
        usdn.approve(address(wusdn), type(uint256).max);

        wusdn.mint(30 * 10 ** usdnDecimals, USER_1);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        wusdn.mint(60 * 10 ** usdnDecimals, USER_1);

        assertApproxEqAbs(wusdn.totalAssets(), wusdn.convertToAssets(90 * 10 ** usdnDecimals), 1, "total assets");
        assertEq(wusdn.totalSupply(), 90 * 10 ** usdnDecimals, "total supply");
    }
}
