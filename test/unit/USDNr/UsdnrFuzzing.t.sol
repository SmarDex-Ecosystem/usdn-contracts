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
     */
    function testFuzz_wrapRebaseUnwrap(uint256 seed0, uint256 seed1, uint256 seed2, uint256 seed3, uint256 seed4)
        public
    {
        uint256 initialDivisor = _bound(seed0, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        usdn.rebase(initialDivisor);

        uint256 contractInitialUsdnBalance = _bound(seed1, 0, usdn.maxTokens() - 1);
        usdn.mint(address(usdnr), contractInitialUsdnBalance);

        uint256 userInitialUsdnBalance = _bound(seed2, 1, usdn.maxTokens() - contractInitialUsdnBalance);
        usdn.mint(address(this), userInitialUsdnBalance);

        /* -------------------------------------------------------------------------- */
        /*                                    WRAP                                    */
        /* -------------------------------------------------------------------------- */

        uint256 usdnAmountToWrap = _bound(seed3, 1, userInitialUsdnBalance);
        usdn.approve(address(usdnr), usdnAmountToWrap);
        usdnr.wrap(usdnAmountToWrap, address(this));
        uint256 userUsdnrBalance = usdnr.balanceOf(address(this));
        assertEq(
            userUsdnrBalance, usdnAmountToWrap, "The usdnr balance of the user must be equal to the wrapped usdn amount"
        );
        assertEq(
            usdn.balanceOf(address(this)),
            userInitialUsdnBalance - usdnAmountToWrap,
            "The usdn balance of the user must be decreased by the wrapped usdn amount"
        );
        assertEq(
            usdn.balanceOf(address(usdnr)),
            contractInitialUsdnBalance + usdnAmountToWrap,
            "The usdn balance of the usdnr contract must be increased by the wrapped usdn amount"
        );

        /* -------------------------------------------------------------------------- */
        /*                                   REBASE                                   */
        /* -------------------------------------------------------------------------- */

        uint256 newDivisor = _bound(seed4, usdn.MIN_DIVISOR(), usdn.divisor());
        usdn.rebase(newDivisor);

        /* -------------------------------------------------------------------------- */
        /*                                   UNWRAP                                   */
        /* -------------------------------------------------------------------------- */

        uint256 contractUsdnBalanceBeforeUnwrap = usdn.balanceOf(address(usdnr));
        uint256 userUsdnBalanceBeforeUnwrap = usdn.balanceOf(address(this));
        usdnr.unwrap(usdnAmountToWrap, address(this));
        uint256 contractUsdnAmountSent = contractUsdnBalanceBeforeUnwrap - usdn.balanceOf(address(usdnr));
        uint256 userUsdnAmountReceivedSent = usdn.balanceOf(address(this)) - userUsdnBalanceBeforeUnwrap;

        assertEq(usdnr.balanceOf(address(this)), 0, "The usdnr balance of the user after unwrap must be zero");
        if (contractUsdnAmountSent <= usdnAmountToWrap && userUsdnAmountReceivedSent <= usdnAmountToWrap) {
            assertApproxEqAbs(
                contractUsdnAmountSent,
                usdnAmountToWrap,
                1,
                "The usdn amount sent by the usdnr contract must be equal or 1 wei less than the initial usdn amount"
            );
            assertApproxEqAbs(
                userUsdnAmountReceivedSent,
                usdnAmountToWrap,
                1,
                "The usdn amount received by the user must be equal or 1 wei less than the initial usdn amount"
            );
        } else {
            revert("The usdn amounts must be lower or equal than the initial amounts");
        }
    }
}
