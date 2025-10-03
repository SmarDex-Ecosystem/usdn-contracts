// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

/// @custom:feature Fuzzing tests of `USDNr` contract
contract TestUsdnrFuzzing is UsdnrTokenFixture {
    /**
     * @custom:scenario A user wraps an amount of usdn to usdnr, a rebase appends, and then unwraps their usdnr
     * @custom:given The divisor is not the initial divisor
     * @custom:and The user wrap an usdn amount to usdnr
     * @custom:and A usdn rebase append
     * @custom:when The user unwrap their usdnr to usdn
     * @custom:then The user's usdnr balance must be zero
     * @custom:and The usdn amount transferred must be equal to the initial usdn amount
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
        usdnr.deposit(usdnAmountToWrap, address(this));
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
        vm.expectEmit();
        emit IERC20.Transfer(address(usdnr), address(this), usdnAmountToWrap);
        usdnr.withdraw(usdnAmountToWrap, address(this));
        uint256 contractUsdnAmountSent = contractUsdnBalanceBeforeUnwrap - usdn.balanceOf(address(usdnr));
        uint256 userUsdnAmountReceived = usdn.balanceOf(address(this)) - userUsdnBalanceBeforeUnwrap;

        assertEq(usdnr.balanceOf(address(this)), 0, "The usdnr balance of the user after unwrap must be zero");
        assertEq(usdnr.totalSupply(), 0, "The usdnr supply after unwrap must be zero");
        assertLe(
            contractUsdnAmountSent,
            usdnAmountToWrap,
            "The usdn amount sent by the usdnr contract must be equal or less than the initial usdn amount"
        );
        assertLe(
            userUsdnAmountReceived,
            usdnAmountToWrap,
            "The usdn amount received by the user must be equal or less than the initial usdn amount"
        );
    }
}
