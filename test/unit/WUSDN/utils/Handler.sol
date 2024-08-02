// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";

import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { ADMIN, USER_1, USER_2, USER_3, USER_4 } from "../../../utils/Constants.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../../../src/Usdn/Wusdn.sol";

/**
 * @title WusdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract WusdnHandler is Wusdn, Test {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // track theoretical tokens
    EnumerableMap.AddressToUintMap private _tokensHandle;
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

    function getTokensOfAddress(address account) external view returns (uint256) {
        (, uint256 valueShares) = _tokensHandle.tryGet(account);
        return valueShares;
    }

    function getElementOfIndex(uint256 index) external view returns (address, uint256) {
        return _tokensHandle.at(index);
    }

    function getLengthOfTokens() external view returns (uint256) {
        return _tokensHandle.length();
    }

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
        uint256 previewShares = _usdn.convertToShares(usdnAmount);
        if (previewShares > usdnSharesUser) previewShares = usdnSharesUser;
        previewShares = previewShares / SHARES_RATIO * SHARES_RATIO;

        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);
        uint256 wusdnBalanceTo = balanceOf(_actors[to]);

        _usdn.approve(address(this), usdnAmount);
        uint256 wrappedAmount = this.wrap(usdnAmount, _actors[to]);
        (, uint256 lastTokens) = _tokensHandle.tryGet(_actors[to]);
        _tokensHandle.set(_actors[to], lastTokens + wrappedAmount);

        assertEq(totalUsdnShares + previewShares, this.totalUsdnShares(), "wrap : total USDN shares in WUSDN");
        assertEq(usdnSharesUser - previewShares, _usdn.sharesOf(msg.sender), "wrap : USDN shares of the user");
        assertEq(wusdnBalanceTo + wrappedAmount, balanceOf(_actors[to]), "wrap : WUSDN balance of the recipient");
    }

    function wrapSharesTest(uint256 to, uint256 usdnShares) external prankUser {
        uint256 usdnSharesUser = _usdn.sharesOf(msg.sender);
        uint256 totalUsdnShares = this.totalUsdnShares();

        if (usdnSharesUser == 0) {
            return;
        }

        console2.log("bound wrap amount");
        usdnShares = bound(usdnShares, 0, usdnSharesUser);
        uint256 wrappedAmountPreview = this.previewWrapShares(usdnShares);

        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);
        uint256 wusdnBalanceTo = balanceOf(_actors[to]);

        _usdn.approve(address(this), _usdn.convertToTokensRoundUp(usdnShares));
        uint256 wrappedAmount = this.wrapShares(usdnShares, _actors[to]);
        (, uint256 lastTokens) = _tokensHandle.tryGet(_actors[to]);
        _tokensHandle.set(_actors[to], lastTokens + wrappedAmount);

        uint256 theoreticalShares = usdnShares / SHARES_RATIO * SHARES_RATIO;
        assertEq(wrappedAmount, wrappedAmountPreview, "wrap : wrapped amount");
        assertEq(totalUsdnShares + theoreticalShares, this.totalUsdnShares(), "wrap : total USDN shares in WUSDN");
        assertEq(usdnSharesUser - theoreticalShares, _usdn.sharesOf(msg.sender), "wrap : USDN shares of the user");
        assertEq(wusdnBalanceTo + wrappedAmount, balanceOf(_actors[to]), "wrap : WUSDN balance of the recipient");
    }

    function unwrapTest(uint256 to, uint256 wusdnAmount) external prankUser {
        uint256 wusdnBalanceUser = balanceOf(msg.sender);
        uint256 totalUsdnShares = this.totalUsdnShares();

        if (wusdnBalanceUser == 0) {
            return;
        }

        console2.log("bound unwrap amount");
        wusdnAmount = bound(wusdnAmount, 0, wusdnBalanceUser);

        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);
        uint256 usdnSharesTo = _usdn.sharesOf(_actors[to]);

        this.unwrap(wusdnAmount, _actors[to]);
        (, uint256 lastTokens) = _tokensHandle.tryGet(msg.sender);
        _tokensHandle.set(msg.sender, lastTokens - wusdnAmount);

        assertEq(
            totalUsdnShares - wusdnAmount * SHARES_RATIO, this.totalUsdnShares(), "unwrap : total USDN shares in WUSDN"
        );
        assertEq(wusdnBalanceUser - wusdnAmount, balanceOf(msg.sender), "unwrap : WUSDN balance of the user");
        assertEq(
            usdnSharesTo + wusdnAmount * SHARES_RATIO,
            _usdn.sharesOf(_actors[to]),
            "unwrap : USDN balance of the recipient"
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

        uint256 lastShares = _tokensHandle.get(msg.sender);
        _tokensHandle.set(msg.sender, lastShares - wusdnAmount);
        (, uint256 toShares) = _tokensHandle.tryGet(_actors[to]);
        _tokensHandle.set(_actors[to], toShares + wusdnAmount);
    }

    function unwrapAll() external {
        for (uint256 i = 0; i < _actors.length; i++) {
            vm.prank(_actors[i]);
            uint256 wusdnAmount = balanceOf(_actors[i]);
            this.unwrap(wusdnAmount);
            (, uint256 lastTokens) = _tokensHandle.tryGet(_actors[i]);
            _tokensHandle.set(_actors[i], lastTokens - wusdnAmount);
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
