// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Usdnr } from "../../../../src/Usdn/Usdnr.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnr } from "../../../../src/interfaces/Usdn/IUsdnr.sol";

/// @dev Handler for USDnr contract to be used in invariant testing
contract UsdnrHandler is Usdnr, Test {
    using FixedPointMathLib for uint256;

    address[] internal _actors;
    address internal _currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        _currentActor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor(IUsdn usdn, address owner, address[] memory actors) Usdnr(usdn, owner) {
        _actors = actors;
    }

    function wrapTest(uint256 usdnAmount, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        uint256 userUsdnBalanceBefore = USDN.balanceOf(_currentActor);
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));

        uint256 userUsdnrBalanceBefore = balanceOf(_currentActor);
        uint256 totalSupplyBefore = totalSupply();

        vm.assume(userUsdnBalanceBefore > 0);
        usdnAmount = bound(usdnAmount, 1, userUsdnBalanceBefore);

        this.wrap(usdnAmount, _currentActor);

        assertEq(balanceOf(_currentActor), userUsdnrBalanceBefore + usdnAmount, "user USDnr balance");
        assertEq(totalSupply(), totalSupplyBefore + usdnAmount, "total USDnr supply");

        assertEq(USDN.balanceOf(_currentActor), userUsdnBalanceBefore - usdnAmount, "user USDN balance");

        uint256 contractUsdnBalanceAfter = USDN.balanceOf(address(this));
        if (contractUsdnBalanceAfter < contractUsdnBalanceBefore + usdnAmount) {
            // account for rounding to the nearest of USDN shares
            assertApproxEqAbs(
                contractUsdnBalanceAfter, contractUsdnBalanceBefore + usdnAmount, 1, "USDN balance in USDnr"
            );
        } else {
            assertEq(contractUsdnBalanceAfter, contractUsdnBalanceBefore + usdnAmount, "USDN balance in USDnr");
        }
    }

    function wrapSharesTest(uint256 usdnSharesAmount, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        uint256 userUsdnBalanceBefore = USDN.balanceOf(_currentActor);
        uint256 userUsdnSharesBefore = USDN.sharesOf(_currentActor);
        uint256 contractUsdnSharesBefore = USDN.sharesOf(address(this));
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));

        uint256 userUsdnrBalanceBefore = balanceOf(_currentActor);
        uint256 totalSupplyBefore = totalSupply();

        vm.assume(userUsdnSharesBefore > 0);
        usdnSharesAmount = bound(usdnSharesAmount, 1, userUsdnSharesBefore);

        uint256 wrappedAmount = usdnSharesAmount / USDN.divisor();
        uint256 previewedAmount = this.previewWrapShares(usdnSharesAmount);

        if (wrappedAmount == 0) {
            vm.expectRevert(IUsdnr.USDnrZeroAmount.selector);
            this.wrapShares(usdnSharesAmount, _currentActor);
            assertEq(previewedAmount, 0, "previewed wrap amount");
            return;
        } else {
            uint256 returnedAmount = this.wrapShares(usdnSharesAmount, _currentActor);
            assertEq(returnedAmount, previewedAmount, "previewed wrap amount");
        }

        assertEq(balanceOf(_currentActor), userUsdnrBalanceBefore + wrappedAmount, "user USDnr balance");
        assertEq(totalSupply(), totalSupplyBefore + wrappedAmount, "total USDnr supply");

        assertEq(USDN.sharesOf(_currentActor), userUsdnSharesBefore - usdnSharesAmount, "user USDN shares");
        assertEq(USDN.sharesOf(address(this)), contractUsdnSharesBefore + usdnSharesAmount, "USDN shares in USDnr");
        assertGe(USDN.balanceOf(address(this)), contractUsdnBalanceBefore + wrappedAmount, "USDN balance in USDnr");
        assertLe(USDN.balanceOf(_currentActor), userUsdnBalanceBefore - wrappedAmount, "user USDN balance");
    }

    function unwrapTest(uint256 usdnrAmount, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        uint256 userUsdnBalanceBefore = USDN.balanceOf(_currentActor);
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));

        uint256 userUsdnrBalanceBefore = balanceOf(_currentActor);
        uint256 totalSupplyBefore = totalSupply();

        vm.assume(userUsdnrBalanceBefore > 0);
        usdnrAmount = bound(usdnrAmount, 1, userUsdnrBalanceBefore);

        this.unwrap(usdnrAmount, _currentActor);

        assertEq(balanceOf(_currentActor), userUsdnrBalanceBefore - usdnrAmount, "user USDnr balance");
        assertEq(totalSupply(), totalSupplyBefore - usdnrAmount, "total USDnr supply");

        assertEq(USDN.balanceOf(address(this)), contractUsdnBalanceBefore - usdnrAmount, "USDN balance in USDnr");
        assertEq(USDN.balanceOf(_currentActor), userUsdnBalanceBefore + usdnrAmount, "user USDN balance");
    }

    function withdrawYieldTest() external {
        uint256 ownerUsdnBalanceBefore = USDN.balanceOf(owner());
        uint256 contractUsdnBalanceBefore = USDN.balanceOf(address(this));
        uint256 balanceRoundedDown = USDN.sharesOf(address(this)) / USDN.divisor();

        uint256 totalSupply = totalSupply();

        if (totalSupply >= balanceRoundedDown) {
            assertApproxEqAbs(
                balanceRoundedDown, totalSupply, 1, "no yield to withdraw, USDN balance should equal total supply"
            );
            return;
        }

        uint256 yield = balanceRoundedDown - totalSupply;

        vm.prank(owner());
        this.withdrawYield(owner());

        assertEq(USDN.balanceOf(address(this)), contractUsdnBalanceBefore - yield, "USDN balance in USDnr");
        assertEq(USDN.balanceOf(owner()), ownerUsdnBalanceBefore + yield, "owner USDN balance");
    }

    function mintUsdn(uint256 usdnShares, uint256 actorIndexSeed) public {
        address actor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        usdnShares = bound(usdnShares, 0, type(uint256).max - USDN.totalShares());
        USDN.mintShares(actor, usdnShares);
    }

    function rebaseTest(uint256 divisor, uint256 rand) public {
        uint256 oldDivisor = USDN.divisor();
        vm.assume(oldDivisor != USDN.MIN_DIVISOR());
        // 0.1% change of rebasing to the minimum possible value
        if (rand % 1000 == 0) {
            USDN.rebase(USDN.MIN_DIVISOR());
            return;
        }
        // rebases at most 50%
        divisor = bound(divisor, USDN.MIN_DIVISOR().max(oldDivisor / 2), oldDivisor - 1);
        USDN.rebase(divisor);
    }

    function giftUsdn(uint256 usdnShares) public {
        usdnShares = bound(usdnShares, 0, type(uint256).max - USDN.totalShares());
        USDN.mintShares(address(this), usdnShares);
    }
}
