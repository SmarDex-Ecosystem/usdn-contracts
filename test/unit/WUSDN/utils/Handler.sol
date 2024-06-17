// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { console2, Test } from "forge-std/Test.sol";

import { USER_1, USER_2, USER_3, USER_4, ADMIN } from "../../../utils/Constants.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../../../src/Usdn/Wusdn.sol";

/**
 * @title WusdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract WusdnHandler is Wusdn, Test {
    Usdn public immutable _usdn;
    address[] _actors = new address[](4);

    constructor(Usdn usdn) Wusdn(usdn) {
        _actors[0] = USER_1;
        _actors[1] = USER_2;
        _actors[2] = USER_3;
        _actors[3] = USER_4;
        _usdn = usdn;
    }

    modifier prankUser() {
        vm.startPrank(msg.sender);
        _;
        vm.stopPrank();
    }

    /* -------------------------------------------------------------------------- */
    /*                    Functions used for invariant testing                    */
    /* -------------------------------------------------------------------------- */

    /* ----------------------------- WUSDN functions ---------------------------- */

    function wrapTest(uint256 to, uint256 usdnAmount) external prankUser {
        uint256 usdnBalanceUser = _usdn.balanceOf(msg.sender);
        uint256 usdnSharesUser = _usdn.sharesOf(msg.sender);
        uint256 totalUsdnShares = this.totalUsdnShares();

        if (usdnSharesUser == 0) {
            return;
        }

        console2.log("bound wrap amount");
        usdnAmount = bound(usdnAmount, 0, usdnBalanceUser);
        uint256 previewWrap = this.previewWrap(usdnAmount);
        uint256 previewShares = _usdn.convertToShares(usdnAmount);
        if (previewShares > usdnSharesUser) previewShares = usdnSharesUser;
        previewShares = previewShares / SHARES_RATIO * SHARES_RATIO;

        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);
        uint256 wusdnBalanceTo = balanceOf(_actors[to]);

        _usdn.approve(address(this), _usdn.balanceOf(msg.sender));
        this.wrap(usdnAmount, _actors[to]);

        assertEq(totalUsdnShares + previewShares, this.totalUsdnShares(), "wrap : total USDN shares in WUSDN");
        assertEq(usdnSharesUser - previewShares, _usdn.sharesOf(msg.sender), "wrap : USDN shares of the user");
        assertEq(wusdnBalanceTo + previewWrap, balanceOf(_actors[to]), "wrap : WUSDN balance of the recipient");
    }

    function unwrapTest(uint256 to, uint256 wusdnAmount) external prankUser {
        uint256 wusdnBalanceUser = balanceOf(msg.sender);
        uint256 totalUsdnShares = this.totalUsdnShares();

        if (wusdnBalanceUser == 0) {
            return;
        }

        console2.log("bound unwrap amount");
        wusdnAmount = bound(wusdnAmount, 0, wusdnBalanceUser);
        uint256 previewUnwrap = this.previewUnwrap(wusdnAmount);

        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);
        uint256 usdnSharesTo = _usdn.sharesOf(_actors[to]);

        this.unwrap(wusdnAmount, _actors[to]);

        assertEq(
            totalUsdnShares - wusdnAmount * SHARES_RATIO, this.totalUsdnShares(), "uwwrap : total USDN shares in WUSDN"
        );
        assertEq(wusdnBalanceUser - wusdnAmount, balanceOf(msg.sender), "uwwrap : WUSDN balance of the user");
        assertEq(
            usdnSharesTo + wusdnAmount * SHARES_RATIO,
            _usdn.sharesOf(_actors[to]),
            "uwwrap : USDN balance of the recipient"
        );
        assertApproxEqAbs(
            previewUnwrap, _usdn.convertToTokens(wusdnAmount * SHARES_RATIO), 1, "uwwrap : preview unwrap"
        );
    }

    function transferTest(uint256 to, uint256 wusdnAmount) external prankUser {
        uint256 wusdnBalance = balanceOf(msg.sender);
        if (wusdnBalance == 0) {
            return;
        }

        console2.log("bound transfer amount");
        wusdnAmount = bound(wusdnAmount, 1, wusdnBalance);
        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);

        this.transfer(_actors[to], wusdnAmount);
    }

    function unwrapAll() external {
        for (uint256 i = 0; i < _actors.length; i++) {
            vm.prank(_actors[i]);
            this.unwrap(balanceOf(_actors[i]));
        }
    }

    /* ----------------------------- USDN functions ----------------------------- */

    function usdnTransferTest(uint256 to, uint256 value) external prankUser {
        uint256 usdnBalance = _usdn.balanceOf(msg.sender);
        if (usdnBalance == 0) {
            return;
        }

        console2.log("bound transfer value");
        value = bound(value, 1, usdnBalance);
        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);

        _usdn.transfer(_actors[to], value);
    }

    function usdnMintTest(uint256 usdnAmount) external {
        uint256 maxTokens = _usdn.maxTokens();
        uint256 totalSupply = _usdn.totalSupply();

        if (totalSupply >= maxTokens - 1) {
            return;
        }

        console2.log("bound mint value");
        usdnAmount = bound(usdnAmount, 1, maxTokens - totalSupply - 1);

        vm.prank(ADMIN);
        _usdn.mint(msg.sender, usdnAmount);
    }

    function usdnBurnTest(uint256 usdnAmount) external prankUser {
        uint256 usdnBalance = _usdn.balanceOf(msg.sender);
        if (usdnBalance == 0) {
            return;
        }

        console2.log("bound burn value");
        usdnAmount = bound(usdnAmount, 1, usdnBalance);

        _usdn.burn(usdnAmount);
    }

    function usdnRebaseTest(uint256 newDivisor) external {
        uint256 divisor = _usdn.divisor();
        uint256 MIN_DIVISOR = _usdn.MIN_DIVISOR();

        if (divisor == MIN_DIVISOR) {
            return;
        }

        console2.log("bound divisor");
        newDivisor = bound(newDivisor, MIN_DIVISOR, divisor - 1);

        vm.prank(ADMIN);
        _usdn.rebase(newDivisor);
    }
}
