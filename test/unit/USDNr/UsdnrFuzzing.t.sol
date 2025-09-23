// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

/// @custom:feature Fuzzing tests of `USDNr` contract
contract TestUsdnrFuzzing is UsdnrTokenFixture {
    /**
     * @custom:scenario A user wraps their usdn balance to usdnr, a rebase appends, and then unwraps their usdnr
     * @custom:given A deployed usdn
     * @custom:and A deployed usdnr
     * @custom:and The user has a usdn balance
     * @custom:when The scenario appends
     * @custom:then The user's usdn balance must be equal to the initial usdn balance
     * @custom:and The user's usdnr balance must be zero
     * @param initialUsdnBalance The initial usdn balance to mint to the user
     * @param newDivisor The new usdn divisor to set
     */
    function testFuzz_wrapRebaseUnwrap(uint256 initialUsdnBalance, uint256 newDivisor) public {
        initialUsdnBalance = _bound(initialUsdnBalance, 1, usdn.maxTokens());
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
