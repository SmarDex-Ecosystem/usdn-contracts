// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature Formal verification of the USDN token functions
 * @custom:background Given MAX_TOKENS, a maximum amount of tokens that can exist
 */
contract TestUsdnHalmos is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
    }

    /**
     * @custom:scenario Convert an amount of tokens to the corresponding amount of shares, then back to tokens
     * @custom:given A divisor between MAX_DIVISOR and MIN_DIVISOR
     * @custom:and An amount of tokens between 0 and MAX_TOKENS
     * @custom:when The tokens are converted to shares and back to tokens
     * @custom:then The result is the same as the original amount of tokens
     * @param divisor The divisor to use
     * @param tokens The amount of tokens to convert
     */
    function check_convertBetweenTokensAndShares(uint256 divisor, uint256 tokens) public {
        vm.assume(divisor >= 1e9 && divisor <= 1e18);
        vm.assume(tokens <= type(uint256).max / divisor);

        if (divisor < 1e18) {
            usdn.rebase(divisor);
        }

        uint256 shares = usdn.convertToShares(tokens);
        uint256 tokensOut = usdn.convertToTokens(shares);

        assertEq(tokens, tokensOut);
    }
}
