// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Wusdn4626 } from "../../../../src/Usdn/Wusdn4626.sol";

contract Wusdn4626Handler is Wusdn4626, Test {
    address public constant USER_1 = address(1);
    address public constant USER_2 = address(2);
    address public constant USER_3 = address(3);
    address public constant USER_4 = address(4);

    // track theoretical tokens
    mapping(address => uint256) private _wusdn4626Shares;
    address[] _actors = new address[](4);
    address internal _currentActor;

    constructor() Wusdn4626() {
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

    function depositTest(uint256 assets, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 vaultBalanceUser = balanceOf(_currentActor);
        uint256 usdnBalanceUser = USDN.balanceOf(_currentActor);
        vm.assume(usdnBalanceUser > 0);
        assets = bound(assets, 1, usdnBalanceUser);

        uint256 preview = this.previewDeposit(assets);
        uint256 shares = this.deposit(assets, _currentActor);

        assertLe(preview, shares, "deposit: preview property");
        assertApproxEqAbs(preview, shares, 1, "deposit: preview max 1 wei off");
        assertEq(USDN.balanceOf(_currentActor), usdnBalanceUser - assets, "deposit: usdn user balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser + shares, "deposit: 4626 user balance property");

        _wusdn4626Shares[_currentActor] += shares;
    }

    function mintTest(uint256 shares, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 vaultBalanceUser = balanceOf(_currentActor);
        uint256 usdnBalanceUser = USDN.balanceOf(_currentActor);
        uint256 maxShares = this.previewDeposit(usdnBalanceUser);
        vm.assume(maxShares > 0);
        shares = bound(shares, 1, maxShares);

        uint256 preview = this.previewMint(shares);
        uint256 assets = this.mint(shares, _currentActor);

        assertGe(preview, assets, "mint: preview property");
        assertApproxEqAbs(preview, assets, 1, "mint: preview max 1 wei off");
        assertEq(USDN.balanceOf(_currentActor), usdnBalanceUser - assets, "mint: usdn user balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser + shares, "mint: 4626 user balance property");

        _wusdn4626Shares[_currentActor] += shares;
    }

    function withdrawTest(uint256 assets, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 usdnBalanceUser = USDN.balanceOf(_currentActor);
        uint256 vaultBalanceUser = balanceOf(_currentActor);

        assets = bound(assets, 0, this.maxWithdraw(_currentActor));

        uint256 preview = this.previewWithdraw(assets);
        uint256 shares = this.withdraw(assets, _currentActor, _currentActor);

        assertEq(preview, shares, "withdraw: preview property");
        assertApproxEqAbs(preview, shares, 1, "withdraw: preview property max 1 wei off");
        assertEq(USDN.balanceOf(_currentActor), usdnBalanceUser + assets, "withdraw: usdn user balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser - shares, "withdraw: 4626 user balance property");

        _wusdn4626Shares[_currentActor] -= shares;
    }

    function redeemTest(uint256 shares, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 usdnBalanceUser = USDN.balanceOf(_currentActor);
        uint256 vaultBalanceUser = balanceOf(_currentActor);

        shares = bound(shares, 0, this.maxRedeem(_currentActor));

        uint256 preview = this.previewRedeem(shares);
        uint256 assets = this.redeem(shares, _currentActor, _currentActor);

        assertLe(preview, assets, "redeem: preview property");
        assertApproxEqAbs(preview, assets, 1, "redeem: preview property max 1 wei off");
        assertEq(USDN.balanceOf(_currentActor), usdnBalanceUser + assets, "redeem: usdn user balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser - shares, "redeem: 4626 user balance property");

        _wusdn4626Shares[_currentActor] -= shares;
    }

    function getGhostTotBal() public view returns (uint256 totBalance_) {
        for (uint256 i; i < _actors.length; i++) {
            totBalance_ += _wusdn4626Shares[_actors[i]];
        }
    }
}
