// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

/// @custom:feature Fuzzing tests of `USDNr` contract
contract TestUsdnrFuzzing is UsdnrTokenFixture {
    /**
     * @custom:scenario A user wraps their usdn balance to usdnr, a rebase appends, and then unwraps their usdnr
     * @custom:given The user wrap their usdn balance to usdnr
     * @custom:and A usdn rebase append
     * @custom:when The user unwrap their usdnr to usdn
     * @custom:then The user's usdn balance must be equal to the initial usdn balance
     * @custom:and The user's usdnr balance must be zero
     * @param seed0 The seed to bound the first divisor
     * @param seed1 The seed to bound the initial usdn balance to mint to the user
     * @param seed2 The seed to bound the second divisor
     */
    function testFuzz_wrapRebaseUnwrap(uint256 seed0, uint256 seed1, uint256 seed2) public {
        uint256 newDivisor = _bound(seed0, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        usdn.rebase(newDivisor);
        uint256 initialUsdnBalance = _bound(seed1, 1, usdn.maxTokens());
        usdn.mint(address(this), initialUsdnBalance);

        /* -------------------------------------------------------------------------- */
        /*                                    WRAP                                    */
        /* -------------------------------------------------------------------------- */

        usdn.approve(address(usdnr), initialUsdnBalance);
        usdnr.wrap(initialUsdnBalance, address(this));
        uint256 usdnrBalance = usdnr.balanceOf(address(this));
        assertEq(
            usdnrBalance, initialUsdnBalance, "The usdnr balance of the user must be equal to the initial usdn balance"
        );
        assertEq(usdn.balanceOf(address(this)), 0, "The usdn balance of the user must be zero");
        assertEq(
            usdn.balanceOf(address(usdnr)),
            initialUsdnBalance,
            "The usdn balance of the usdnr contract must be equal to the initial usdn balance"
        );

        /* -------------------------------------------------------------------------- */
        /*                                   REBASE                                   */
        /* -------------------------------------------------------------------------- */

        newDivisor = _bound(seed2, usdn.MIN_DIVISOR(), usdn.divisor());
        usdn.rebase(newDivisor);

        /* -------------------------------------------------------------------------- */
        /*                                   UNWRAP                                   */
        /* -------------------------------------------------------------------------- */

        usdnr.unwrap(usdnrBalance, address(this));
        assertEq(
            usdn.balanceOf(address(this)),
            initialUsdnBalance,
            "The usdn balance of the user after unwrap must be equal to the initial usdn balance"
        );
        assertEq(usdnr.balanceOf(address(this)), 0, "The usdnr balance of the user after unwrap must be zero");
    }
}
