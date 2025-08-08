// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../../../src/Usdn/Wusdn.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";
import { Wusdn4626 } from "../../../../src/utils/Wusdn4626.sol";

contract Wusdn4626Handler is Wusdn4626, Test {
    address public constant USER_1 = address(1);
    address public constant USER_2 = address(2);
    address public constant USER_3 = address(3);
    address public constant USER_4 = address(4);
    IUsdn public immutable usdn;

    // track theoretical tokens
    mapping(address => uint256) private _wusdn4626Shares;
    address[] _actors = new address[](4);
    address internal _currentActor;
    uint256 _price;

    constructor() Wusdn4626() {
        _actors[0] = USER_1;
        _actors[1] = USER_2;
        _actors[2] = USER_3;
        _actors[3] = USER_4;

        usdn = WUSDN.USDN();
    }

    modifier useActor(uint256 actorIndexSeed) {
        _currentActor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    function depositTest(uint256 assets, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 usdnBalanceUser = usdn.balanceOf(_currentActor);
        uint256 wusdnBalanceProtocol = WUSDN.balanceOf(address(this));
        uint256 vaultBalanceUser = balanceOf(_currentActor);

        vm.assume(usdnBalanceUser > 0);
        assets = bound(assets, 1, usdnBalanceUser);

        uint256 preview = Wusdn4626(address(this)).previewDeposit(assets);
        uint256 shares = Wusdn4626(address(this)).deposit(assets, _currentActor);
        uint256 newPrice = convertToAssets(1 ether);

        assertGe(newPrice, _price, "deposit: price property");
        assertEq(preview, shares, "deposit: preview property");
        assertEq(usdn.balanceOf(_currentActor), usdnBalanceUser - assets, "deposit: usdn user balance property");
        assertEq(WUSDN.balanceOf(address(this)), wusdnBalanceProtocol + shares, "deposit: wusdn vault balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser + shares, "deposit: 4626 user balance property");

        _wusdn4626Shares[_currentActor] += shares;
        _price = newPrice;
    }

    function mintTest(uint256 shares, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 usdnBalanceUser = usdn.balanceOf(_currentActor);
        uint256 wusdnBalanceProtocol = WUSDN.balanceOf(address(this));
        uint256 vaultBalanceUser = balanceOf(_currentActor);
        uint256 sharesOf = usdn.sharesOf(_currentActor) / WUSDN.SHARES_RATIO();

        vm.assume(sharesOf > 0);
        shares = bound(shares, 1, sharesOf);

        uint256 preview = Wusdn4626(address(this)).previewMint(shares);
        uint256 assets = Wusdn4626(address(this)).mint(shares, _currentActor);
        uint256 newPrice = convertToAssets(1 ether);

        assertGe(newPrice, _price, "deposit: price property");
        assertEq(preview, assets, "deposit: preview property");
        assertEq(usdn.balanceOf(_currentActor), usdnBalanceUser - assets, "mint: usdn user balance property");
        assertEq(WUSDN.balanceOf(address(this)), wusdnBalanceProtocol + shares, "mint: wusdn vault balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser + shares, "mint: 4626 user balance property");

        _wusdn4626Shares[_currentActor] += shares;
        _price = newPrice;
    }

    function withdrawTest(uint256 assets, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 usdnBalanceUser = usdn.balanceOf(_currentActor);
        uint256 wusdnBalanceProtocol = WUSDN.balanceOf(address(this));
        uint256 vaultBalanceUser = balanceOf(_currentActor);

        assets = bound(assets, 0, balanceOf(_currentActor));

        uint256 preview = Wusdn4626(address(this)).previewWithdraw(assets);
        uint256 shares = Wusdn4626(address(this)).withdraw(assets, _currentActor, _currentActor);
        uint256 newPrice = convertToAssets(1 ether);

        assertGe(newPrice, _price, "withdraw: price property");
        assertEq(preview, shares, "withdraw: preview property");
        assertEq(usdn.balanceOf(_currentActor), usdnBalanceUser + assets, "withdraw: usdn user balance property");
        assertEq(
            WUSDN.balanceOf(address(this)), wusdnBalanceProtocol - shares, "withdraw: wusdn vault balance property"
        );
        assertEq(balanceOf(_currentActor), vaultBalanceUser - shares, "withdraw: 4626 user balance property");

        _wusdn4626Shares[_currentActor] -= shares;
        _price = newPrice;
    }

    function redeemTest(uint256 shares, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint256 usdnBalanceUser = usdn.balanceOf(_currentActor);
        uint256 wusdnBalanceProtocol = WUSDN.balanceOf(address(this));
        uint256 vaultBalanceUser = balanceOf(_currentActor);

        shares = bound(shares, 0, balanceOf(_currentActor));

        uint256 preview = Wusdn4626(address(this)).previewRedeem(shares);
        uint256 assets = Wusdn4626(address(this)).redeem(shares, _currentActor, _currentActor);
        uint256 newPrice = convertToAssets(1 ether);

        assertGe(newPrice, _price, "redeem: price property");
        assertEq(preview, shares, "redeem: preview property");
        assertEq(usdn.balanceOf(_currentActor), usdnBalanceUser + assets, "redeem: usdn user balance property");
        assertEq(WUSDN.balanceOf(address(this)), wusdnBalanceProtocol - shares, "redeem: wusdn vault balance property");
        assertEq(balanceOf(_currentActor), vaultBalanceUser - shares, "redeem: 4626 user balance property");

        _wusdn4626Shares[_currentActor] -= shares;
        _price = newPrice;
    }

    function getGhostTotBal() public view returns (uint256 totBalance_) {
        for (uint256 i; i < _actors.length; i++) {
            totBalance_ += _wusdn4626Shares[_actors[i]];
        }
    }
}
