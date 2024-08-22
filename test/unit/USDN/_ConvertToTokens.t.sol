// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnTokenFixture } from "./utils/Fixtures.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";

/// @custom:feature The `_convertToTokens` function of `USDN`
contract TestUsdnConvertToTokens is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario The divisor has an invalid value
     * @custom:when The divisor is set to 0 or 1
     * @custom:then The conversion reverts with the `UsdnInvalidDivisor` error
     */
    function test_RevertWhen_divisorIsTooSmall() public {
        vm.expectRevert(UsdnInvalidDivisor.selector);
        usdn.i_convertToTokens(1 ether, Usdn.Rounding.Down, 0);

        vm.expectRevert(UsdnInvalidDivisor.selector);
        usdn.i_convertToTokens(1 ether, Usdn.Rounding.Down, 1);
    }

    /**
     * @custom:scenario Convert shares to token rounding down
     * @custom:given The USDN was rebased with a random divisor in the valid range
     * @custom:when We convert a random amount of shares to tokens rounding down
     * @custom:then The result is the integer quotient of shares divided by the divisor
     */
    function testFuzz_convertToTokensDown(uint256 divisor, uint256 shares) public view {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());

        uint256 tokens = usdn.i_convertToTokens(shares, Usdn.Rounding.Down, divisor);
        assertEq(tokens, shares / divisor);
    }

    /**
     * @custom:scenario Convert shares to token rounding up
     * @custom:given The USDN was rebased with a random divisor in the valid range
     * @custom:when We convert a random amount of shares to tokens rounding up
     * @custom:then The resulting amount of tokens is the result of dividing shares by the divisor and rounding up
     * @custom:but If the amount of corresponding shares would exceed uint256.max we round down
     */
    function testFuzz_convertToTokensUp(uint256 divisor, uint256 shares) public view {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());

        uint256 tokens = usdn.i_convertToTokens(shares, Usdn.Rounding.Up, divisor);

        if (shares / divisor >= type(uint256).max / divisor) {
            // the amount of tokens cannot be equivalent to a number of shares larger than uint256.max
            assertEq(tokens, shares / divisor, "uint max");
        } else {
            assertEq(tokens, FixedPointMathLib.divUp(shares, divisor), "regular case");
        }
    }

    /**
     * @custom:scenario Convert shares to token rounding towards the closest integer
     * @custom:given The USDN was rebased with a random divisor in the valid range
     * @custom:when We convert a random amount of shares to tokens rounding towards the closest integer
     * @custom:then The resulting amount of tokens is the result of dividing shares by the divisor and rounding to the *
     * closest integer
     * @custom:but If the amount of corresponding shares would exceed uint256.max we round down
     */
    function testFuzz_convertToTokensClosest(uint256 divisor, uint256 shares) public view {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());

        uint256 tokens = usdn.i_convertToTokens(shares, Usdn.Rounding.Closest, divisor);

        if (shares / divisor >= type(uint256).max / divisor) {
            // the amount of tokens cannot be equivalent to a number of shares larger than uint256.max
            assertEq(tokens, shares / divisor, "uint max");
        } else {
            uint256 tokensDown = shares / divisor;
            uint256 sharesDown = tokensDown * divisor;
            uint256 sharesUp = (tokensDown + 1) * divisor;
            uint256 tokensClosest = sharesUp - shares <= shares - sharesDown ? tokensDown + 1 : tokensDown;
            assertEq(tokens, tokensClosest, "regular case");
        }
    }

    /**
     * @custom:scenario Convert shares to token when the integer division has no remainder
     * @custom:given The USDN was rebased with a random divisor in the valid range
     * @custom:and The amount of shares is a multiple of the divisor
     * @custom:when We convert the amount of shares to tokens
     * @custom:then The resulting amount of tokens is the integer quotient of shares divided by the divisor, regardless
     * of the rounding mode
     */
    function testFuzz_convertToTokensNoRemainder(uint256 divisor, uint256 multiple) public view {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        multiple = bound(multiple, 0, type(uint256).max / divisor);

        uint256 shares = multiple * divisor;
        uint256 tokens = usdn.i_convertToTokens(shares, Usdn.Rounding.Up, divisor);
        assertEq(tokens, multiple);
        tokens = usdn.i_convertToTokens(shares, Usdn.Rounding.Closest, divisor);
        assertEq(tokens, multiple);
        tokens = usdn.i_convertToTokens(shares, Usdn.Rounding.Down, divisor);
        assertEq(tokens, multiple);
    }
}
