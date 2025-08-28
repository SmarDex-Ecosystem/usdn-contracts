// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Usdn4626 } from "../../../../src/Usdn/Usdn4626.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";

contract Usdn4626Handler is Usdn4626, Test {
    address public constant USER_1 = address(1);
    address public constant USER_2 = address(2);
    address public constant USER_3 = address(3);
    address public constant USER_4 = address(4);

    // track theoretical tokens
    mapping(address => uint256) private _shares;
    address[] _actors = new address[](4);
    address internal _currentActor;

    constructor(IUsdn usdn) Usdn4626(usdn) {
        _actors[0] = USER_1;
        _actors[1] = USER_2;
        _actors[2] = USER_3;
        _actors[3] = USER_4;
    }

    modifier useActor(uint256 actorIndexSeed) {
        _currentActor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    function depositTest(uint256 assets, uint256 actorIndexSeed, uint256 receiverIndexSeed)
        public
        useActor(actorIndexSeed)
    {
        address receiver = _actors[bound(receiverIndexSeed, 0, _actors.length - 1)];
        uint256 vaultBalanceReceiver = balanceOf(receiver);
        uint256 usdnBalanceUser = USDN.balanceOf(_currentActor);
        uint256 usdnShares = USDN.sharesOf(address(this));
        vm.assume(usdnBalanceUser > 0);
        assets = bound(assets, 1, usdnBalanceUser);

        uint256 preview = this.previewDeposit(assets);
        vm.assume(preview > 0); // can only deposit if we can mint at least 1 wei of wrapper
        // since we gift extra tokens to the depositor, we can calculate the expected amount
        uint256 expectedShares = (
            FixedPointMathLib.min(USDN.sharesOf(_currentActor), USDN.convertToShares(assets))
                + (USDN.sharesOf(address(this)) - totalSupply() * SHARES_RATIO)
        ) / SHARES_RATIO;
        uint256 shares = this.deposit(assets, receiver);

        assertLe(preview, shares, "deposit: preview property");
        assertEq(shares, expectedShares, "deposit: expected shares");
        assertEq(USDN.balanceOf(_currentActor), usdnBalanceUser - assets, "deposit: usdn user balance property");
        assertEq(balanceOf(receiver), vaultBalanceReceiver + shares, "deposit: 4626 receiver balance property");
        assertEq(USDN.sharesOf(address(this)), usdnShares + USDN.convertToShares(assets), "deposit: 4626 usdn shares");

        _shares[receiver] += shares;
    }

    function mintTest(uint256 shares, uint256 actorIndexSeed, uint256 receiverIndexSeed)
        public
        useActor(actorIndexSeed)
    {
        address receiver = _actors[bound(receiverIndexSeed, 0, _actors.length - 1)];
        uint256 vaultBalanceReceiver = balanceOf(receiver);
        uint256 usdnBalanceUser = USDN.balanceOf(_currentActor);
        uint256 usdnShares = USDN.sharesOf(address(this));
        uint256 maxShares = this.previewDeposit(usdnBalanceUser);
        vm.assume(maxShares > 0);
        shares = bound(shares, 1, maxShares);

        uint256 preview = this.previewMint(shares);
        uint256 assets = this.mint(shares, receiver);

        assertGe(preview, assets, "mint: preview property");
        assertApproxEqAbs(preview, assets, 1, "mint: preview max 1 wei off");
        assertEq(USDN.balanceOf(_currentActor), usdnBalanceUser - assets, "mint: usdn user balance property");
        assertEq(balanceOf(receiver), vaultBalanceReceiver + shares, "mint: 4626 receiver balance property");
        assertEq(USDN.sharesOf(address(this)), usdnShares + shares * SHARES_RATIO, "mint: 4626 usdn shares");

        _shares[receiver] += shares;
    }

    function withdrawTest(uint256 assets, uint256 actorIndexSeed, uint256 receiverIndexSeed)
        public
        useActor(actorIndexSeed)
    {
        address receiver = _actors[bound(receiverIndexSeed, 0, _actors.length - 1)];
        uint256 vaultBalanceUser = balanceOf(_currentActor);
        uint256 usdnBalanceReceiver = USDN.balanceOf(receiver);
        uint256 usdnShares = USDN.sharesOf(address(this));
        assets = bound(assets, 0, this.maxWithdraw(_currentActor));

        uint256 preview = this.previewWithdraw(assets);
        uint256 shares = this.withdraw(assets, receiver, _currentActor);

        assertGe(preview, shares, "withdraw: preview property");
        assertApproxEqAbs(preview, shares, 1, "withdraw: preview max 1 wei off");
        assertEq(USDN.balanceOf(receiver), usdnBalanceReceiver + assets, "withdraw: usdn receiver balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser - shares, "withdraw: 4626 user balance property");
        assertEq(USDN.sharesOf(address(this)), usdnShares - USDN.convertToShares(assets), "withdraw: 4626 usdn shares");

        _shares[_currentActor] -= shares;
    }

    function redeemTest(uint256 shares, uint256 actorIndexSeed, uint256 receiverIndexSeed)
        public
        useActor(actorIndexSeed)
    {
        address receiver = _actors[bound(receiverIndexSeed, 0, _actors.length - 1)];
        uint256 vaultBalanceUser = balanceOf(_currentActor);
        uint256 usdnBalanceReceiver = USDN.balanceOf(receiver);
        uint256 usdnShares = USDN.sharesOf(address(this));
        shares = bound(shares, 0, this.maxRedeem(_currentActor));

        uint256 preview = this.previewRedeem(shares);
        uint256 assets = this.redeem(shares, receiver, _currentActor);

        assertLe(preview, assets, "redeem: preview property");
        assertApproxEqAbs(preview, assets, 1, "redeem: preview max 1 wei off");
        assertEq(USDN.balanceOf(receiver), usdnBalanceReceiver + assets, "redeem: usdn receiver balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser - shares, "redeem: 4626 user balance property");
        assertEq(USDN.sharesOf(address(this)), usdnShares - shares * SHARES_RATIO, "redeem: 4626 usdn shares");

        _shares[_currentActor] -= shares;
    }

    function rebaseTest(uint256 divisor, uint256 rand) public {
        uint256 oldDivisor = USDN.divisor();
        vm.assume(oldDivisor != USDN.MIN_DIVISOR());
        // 1% change of rebasing to the minimum possible value
        if (rand % 100 == 0) {
            USDN.rebase(USDN.MIN_DIVISOR());
            return;
        }
        // rebases at most 50%
        divisor = bound(divisor, FixedPointMathLib.max(USDN.MIN_DIVISOR(), oldDivisor / 2), oldDivisor - 1);
        USDN.rebase(divisor);
    }

    function giftUsdn(uint256 amount) public {
        amount = bound(amount, 1, 1e6 ether);
        USDN.mint(address(this), amount);
    }

    function getGhostTotalSupply() public view returns (uint256 totalSupply_) {
        for (uint256 i; i < _actors.length; i++) {
            totalSupply_ += _shares[_actors[i]];
        }
    }

    function redeemAll() public {
        for (uint256 i; i < _actors.length; i++) {
            uint256 balance = balanceOf(_actors[i]);
            if (balance > 0) {
                vm.startPrank(_actors[i]);
                this.redeem(balance, _actors[i], _actors[i]);
                vm.stopPrank();
            }
        }
    }

    function emptyVault() public {
        USDN.mint(USER_1, 1e18);
        vm.startPrank(USER_1);
        this.deposit(1e18, USER_1);
        this.redeem(balanceOf(USER_1), address(0xdead), USER_1);
        vm.stopPrank();
    }
}
