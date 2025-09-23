// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

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
     * @custom:when The `withdrawYield` function is called by the owner
     * @custom:then The yield is successfully withdrawn
     */
    function test_withdrawYield() public {
        usdn.rebase(usdn.divisor() * 90 / 100);
        uint256 yield = usdn.sharesOf(address(usdnr)) / usdn.divisor() - initialDeposit;
        assertGt(usdn.balanceOf(address(usdnr)), initialDeposit);

        usdnr.withdrawYield(address(this));

        assertEq(usdn.balanceOf(address(this)), yield);
        assertEq(usdn.balanceOf(address(usdnr)), initialDeposit);
    }

    /**
     * @custom:scenario Withdraw yield to a specific recipient
     * @custom:when The `withdrawYield` function is called by the owner with a specific recipient address
     * @custom:then The yield is successfully withdrawn to the specified recipient
     */
    function test_withdrawYieldRecipient() public {
        uint256 balanceBefore = usdn.balanceOf(address(this));
        usdn.rebase(usdn.divisor() * 90 / 100);
        uint256 yield = usdn.sharesOf(address(usdnr)) / usdn.divisor() - initialDeposit;
        assertGt(usdn.balanceOf(address(usdnr)), initialDeposit);

        usdnr.withdrawYield(address(1));

        assertEq(usdn.balanceOf(address(1)), yield);
        assertEq(usdn.balanceOf(address(this)), balanceBefore);
        assertEq(usdn.balanceOf(address(usdnr)), initialDeposit);
    }

    /**
     * @custom:scenario Revert when non-owner tries to withdraw yield
     * @custom:when The `withdrawYield` function is called by a non-owner address
     * @custom:then The transaction reverts with an "Ownable: caller is not the owner" error
     */
    function test_revertWhen_withdrawYieldNotOwner() public {
        address nonOwnerUser = address(1);

        vm.prank(nonOwnerUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (nonOwnerUser)));
        usdnr.withdrawYield(nonOwnerUser);
    }

    /**
     * @custom:scenario Revert when trying to withdraw yield with no yield available
     * @custom:when The `withdrawYield` function is called by the owner when there is no yield available
     * @custom:then The transaction reverts with a "USDNrNoYield" error
     */
    function test_revertWhen_withdrawYieldNoYield() public {
        assertEq(usdn.balanceOf(address(usdnr)), usdnr.totalSupply());

        vm.expectRevert(IUsdnr.USDNrNoYield.selector);
        usdnr.withdrawYield(address(this));
    }

    /**
     * @custom:scenario Revert when trying to withdraw yield to the zero address
     * @custom:when The `withdrawYield` function is called by the owner with the zero address as the recipient
     * @custom:then The transaction reverts with a "USDNrZeroRecipient" error
     */
    function test_revertWhen_withdrawYieldZeroRecipient() public {
        vm.expectRevert(IUsdnr.USDNrZeroRecipient.selector);
        usdnr.withdrawYield(address(0));
    }
}
