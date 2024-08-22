// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `convertToShares` and `convertToTokens` functions of `USDN`
 * @custom:background Given the divisor is MAX_DIVISOR at the start
 */
contract TestUsdnConvert is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Converting tokens to shares never reverts
     * @custom:given The divisor is MAX_DIVISOR or MIN_DIVISOR
     * @custom:when The `convertToShares` function is called with MAX_TOKENS
     * @custom:then The call does not revert
     */
    function test_maxShares() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        usdn.convertToShares(usdn.maxTokens());

        usdn.rebase(usdn.MIN_DIVISOR());

        usdn.convertToShares(usdn.maxTokens());
    }

    /**
     * @custom:scenario Converting shares to tokens never reverts
     * @custom:given The divisor is MAX_DIVISOR or MIN_DIVISOR
     * @custom:and The number of shares to convert corresponds to MAX_TOKENS at the current multiplier
     * @custom:when The `convertToTokens` function is called with the number of shares
     * @custom:then The call does not revert
     */
    function test_maxTokens() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        uint256 max_shares = usdn.convertToShares(usdn.maxTokens());
        uint256 tokens = usdn.convertToTokens(max_shares);

        usdn.rebase(usdn.MIN_DIVISOR());

        max_shares = usdn.convertToShares(usdn.maxTokens());
        tokens = usdn.convertToTokens(max_shares);
    }

    /**
     * @custom:scenario Converting tokens to shares when the number of tokens is too large
     * @custom:when The `convertToShares` function is called with a value larger than MAX_TOKENS
     * @custom:then The transaction reverts with `UsdnMaxTokensExceeded`
     */
    function test_RevertWhen_tokenAmountOverflows() public {
        uint256 value = usdn.maxTokens() + 1;
        vm.expectRevert(abi.encodeWithSelector(UsdnMaxTokensExceeded.selector, value));
        usdn.convertToShares(value);
    }
}
