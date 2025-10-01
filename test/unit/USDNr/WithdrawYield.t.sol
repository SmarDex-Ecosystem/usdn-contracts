// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `withdrawYield` function of the `USDnr` contract
contract TestUsdnrWithdrawYield is UsdnrTokenFixture {
    using FixedPointMathLib for uint256;

    uint256 initialDeposit = 100 ether;

    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), initialDeposit);
        usdn.approve(address(usdnr), type(uint256).max);
        usdnr.wrap(initialDeposit, address(this));
    }

    /**
     * @custom:scenario Withdraw yield from the USDnr contract
     * @custom:when The `withdrawYield` function is called by any address
     * @custom:then The yield is successfully withdrawn to the yield recipient
     */
    function test_withdrawYield() public {
        address user = address(1);
        usdn.rebase(usdn.divisor() * 90 / 100);
        uint256 yield = (usdn.sharesOf(address(usdnr)) / usdn.divisor() - initialDeposit).saturatingSub(usdnr.RESERVE());
        address yieldRecipient = usdnr.getYieldRecipient();
        assertEq(usdn.balanceOf(address(usdnr)), initialDeposit + usdnr.RESERVE() + yield, "there should be yield");

        vm.expectEmit();
        emit IUsdnr.USDnrYieldWithdrawn(address(this), yield);
        vm.prank(user);
        usdnr.withdrawYield();

        assertEq(usdn.balanceOf(user), 0, "USDN balance of the user");
        assertEq(usdn.balanceOf(yieldRecipient), yield, "USDN balance of the yield recipient");
        assertEq(usdn.balanceOf(address(usdnr)), initialDeposit + usdnr.RESERVE(), "USDN balance of the USDnr contract");
    }

    /**
     * @custom:scenario Revert when trying to withdraw yield with no yield available
     * @custom:when The `withdrawYield` function is called when there is no yield available
     * @custom:then The transaction reverts with a "USDnrNoYield" error
     */
    function test_revertWhen_withdrawYieldNoYield() public {
        assertEq(usdn.balanceOf(address(usdnr)), usdnr.totalSupply());

        vm.expectRevert(IUsdnr.USDnrNoYield.selector);
        usdnr.withdrawYield();
    }

    /**
     * @custom:scenario Revert when trying to withdraw yield before the reserve is reached
     * @custom:when The `withdrawYield` function is called when the reserve is not yet reached
     * @custom:then The transaction reverts with a "USDnrNoYield" error
     */
    function test_revertWhen_withdrawYieldBeforeReserve() public {
        usdn.mint(address(usdnr), usdnr.RESERVE());
        assertEq(usdn.balanceOf(address(usdnr)), usdnr.totalSupply() + usdnr.RESERVE());

        vm.expectRevert(IUsdnr.USDnrNoYield.selector);
        usdnr.withdrawYield();
    }
}
