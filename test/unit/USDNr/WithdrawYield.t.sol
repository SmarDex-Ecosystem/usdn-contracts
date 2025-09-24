// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `withdrawYield` function of the `USDNr` contract
contract TestUsdnrWithdrawYield is UsdnrTokenFixture {
    uint256 initialDeposit = 100 ether;

    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), initialDeposit);
        usdn.approve(address(usdnr), type(uint256).max);
        usdnr.wrap(initialDeposit, address(this));
    }

    /**
     * @custom:scenario Withdraw yield from the USDNr contract
     * @custom:when The `withdrawYield` function is called
     * @custom:then The yield is successfully withdrawn
     */
    function test_withdrawYield() public {
        usdn.rebase(usdn.divisor() * 90 / 100);
        uint256 yield = usdn.sharesOf(address(usdnr)) / usdn.divisor() - initialDeposit;
        assertGt(usdn.balanceOf(address(usdnr)), initialDeposit);

        vm.prank(address(1));
        usdnr.withdrawYield();

        assertEq(usdn.balanceOf(address(this)), yield);
        assertEq(usdn.balanceOf(address(usdnr)), initialDeposit);
    }

    /**
     * @custom:scenario Withdraw yield to a specific recipient
     * @custom:given The yield recipient is set, by the owner, to a specific address
     * @custom:when The `withdrawYield` function is called
     * @custom:then The yield is successfully withdrawn to the specified recipient
     */
    function test_withdrawYieldRecipient() public {
        uint256 balanceBefore = usdn.balanceOf(address(this));
        usdn.rebase(usdn.divisor() * 90 / 100);
        uint256 yield = usdn.sharesOf(address(usdnr)) / usdn.divisor() - initialDeposit;
        assertGt(usdn.balanceOf(address(usdnr)), initialDeposit);

        usdnr.setYieldRecipient(address(1));
        assertEq(usdnr.getYieldRecipient(), address(1), "yield recipient");

        usdnr.withdrawYield();

        assertEq(usdn.balanceOf(address(1)), yield);
        assertEq(usdn.balanceOf(address(this)), balanceBefore);
        assertEq(usdn.balanceOf(address(usdnr)), initialDeposit);
    }

    /**
     * @custom:scenario Revert when trying to withdraw yield with no yield available
     * @custom:when The `withdrawYield` function is called when there is no yield available
     * @custom:then The transaction reverts with a "USDNrNoYield" error
     */
    function test_revertWhen_withdrawYieldNoYield() public {
        assertEq(usdn.balanceOf(address(usdnr)), usdnr.totalSupply());

        vm.expectRevert(IUsdnr.USDNrNoYield.selector);
        usdnr.withdrawYield();
    }
}
