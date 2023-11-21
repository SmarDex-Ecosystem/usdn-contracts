// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `convertToShares` and `convertToTokens` functions of `USDN`
 */
contract TestUsdnConvert is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_maxShares() public {
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));

        usdn.convertToShares(usdn.maxTokens());

        usdn.adjustMultiplier(1 ether);

        usdn.convertToShares(usdn.maxTokens());
    }

    function test_maxTokens() public {
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));

        uint256 max_shares = usdn.convertToShares(usdn.maxTokens());
        uint256 tokens = usdn.convertToTokens(max_shares);

        usdn.adjustMultiplier(1 ether);

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
