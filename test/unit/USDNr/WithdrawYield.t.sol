// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `withdrawYield` function of the `USDnr` contract
contract TestUsdnrWithdrawYield is UsdnrTokenFixture {
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
        usdn.rebase(usdn.divisor() * 90 / 100);
        uint256 yield = usdn.sharesOf(address(usdnr)) / usdn.divisor() - initialDeposit;
        address yieldRecipient = usdnr.getYieldRecipient();
        assertGt(usdn.balanceOf(address(usdnr)), initialDeposit);

        vm.expectEmit();
        emit IUsdnr.USDnrYieldWithdrawn(address(this), yield);
        vm.prank(address(1));
        usdnr.withdrawYield();

        assertEq(usdn.balanceOf(address(1)), 0);
        assertEq(usdn.balanceOf(yieldRecipient), yield);
        assertEq(usdn.balanceOf(address(usdnr)), initialDeposit);
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
}
