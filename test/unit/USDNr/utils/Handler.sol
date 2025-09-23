// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Usdnr } from "../../../../src/Usdn/Usdnr.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnr } from "../../../../src/interfaces/Usdn/IUsdnr.sol";

contract StakingDecayRateHandler is Usdnr, Test {
    address[] internal _actors;
    address internal _currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        _currentActor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor(IUsdn usdn, address owner) Usdnr(usdn, owner) { }

    function wrapTest(uint256 usdnAmount, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        uint256 userUsdnBalanceBefore = USDN.balanceOf(_currentActor);
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));
        uint256 userUsdnrBalanceBefore = this.balanceOf(_currentActor);
        uint256 totalSupplyBefore = this.totalSupply();

        vm.assume(userUsdnBalanceBefore > 0);
        usdnAmount = bound(usdnAmount, 1, userUsdnBalanceBefore);

        this.wrap(usdnAmount);

        assertEq(this.balanceOf(_currentActor), userUsdnrBalanceBefore + usdnAmount, "user USDNr balance");
        assertEq(this.totalSupply(), totalSupplyBefore + usdnAmount, "total USDNr supply");

        assertEq(USDN.balanceOf(address(this)), contractUsdnBalanceBefore + usdnAmount, "USDN balance in USDNr");
        assertEq(USDN.balanceOf(_currentActor), userUsdnBalanceBefore - usdnAmount, "user USDN balance");
    }

    function wrapSharesTest(uint256 usdnSharesAmount, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        uint256 userUsdnBalanceBefore = USDN.balanceOf(_currentActor);
        uint256 userUsdnSharesBefore = USDN.sharesOf(_currentActor);
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));
        uint256 userUsdnrBalanceBefore = this.balanceOf(_currentActor);
        uint256 totalSupplyBefore = this.totalSupply();

        vm.assume(userUsdnSharesBefore > 0);
        usdnSharesAmount = bound(usdnSharesAmount, 1, userUsdnSharesBefore);

        uint256 wrappedAmount = usdnSharesAmount / USDN.divisor();
        uint256 previewedAmount = this.previewWrapShares(usdnSharesAmount);

        if (wrappedAmount == 0) {
            vm.expectRevert(IUsdnr.USDNrZeroAmount.selector);
            this.wrapShares(usdnSharesAmount, _currentActor);
            assertEq(previewedAmount, 0, "previewed wrap amount");
            return;
        } else {
            uint256 returnedAmount = this.wrapShares(usdnSharesAmount, _currentActor);
            assertEq(returnedAmount, previewedAmount, "previewed wrap amount");
        }

        assertEq(this.balanceOf(_currentActor), userUsdnrBalanceBefore + wrappedAmount, "user USDNr balance");
        assertEq(this.totalSupply(), totalSupplyBefore + wrappedAmount, "total USDNr supply");

        assertEq(USDN.balanceOf(address(this)), contractUsdnBalanceBefore + wrappedAmount, "USDN balance in USDNr");
        assertEq(USDN.balanceOf(_currentActor), userUsdnBalanceBefore - wrappedAmount, "user USDN balance");
    }

    function unwrapTest(uint256 usdnrAmount, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        uint256 userUsdnBalanceBefore = USDN.balanceOf(_currentActor);
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));
        uint256 userUsdnrBalanceBefore = this.balanceOf(_currentActor);
        uint256 totalSupplyBefore = this.totalSupply();

        usdnrAmount = bound(usdnrAmount, 1, userUsdnrBalanceBefore);

        this.unwrap(usdnrAmount);

        assertEq(this.balanceOf(_currentActor), userUsdnrBalanceBefore - usdnrAmount, "user USDNr balance");
        assertEq(this.totalSupply(), totalSupplyBefore - usdnrAmount, "total USDNr supply");

        assertEq(USDN.balanceOf(address(this)), contractUsdnBalanceBefore + usdnrAmount, "USDN balance in USDNr");
        assertEq(USDN.balanceOf(_currentActor), userUsdnBalanceBefore - usdnrAmount, "user USDN balance");
    }

    function withdrawYieldTest() external {
        uint256 ownerUsdnBalanceBefore = USDN.balanceOf(owner());
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));
        uint256 yield = USDN.sharesOf(address(this)) / USDN.divisor() - totalSupply();

        vm.prank(owner());
        this.withdrawYield(owner());

        assertEq(USDN.balanceOf(address(this)), contractUsdnBalanceBefore - yield, "USDN balance in USDNr");
        assertEq(USDN.balanceOf(owner()), ownerUsdnBalanceBefore + yield, "owner USDN balance");
    }
}
