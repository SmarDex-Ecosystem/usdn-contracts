// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2, Test } from "forge-std/Test.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";

import { Usdn } from "src/Usdn/Usdn.sol";
import { Wusdn } from "src/Usdn/Wusdn.sol";

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

    /* ------------------ Functions used for invariant testing ------------------ */

    function wrapTest(uint256 usdnAmount) external {
        uint256 usdnBalance = _usdn.balanceOf(msg.sender);
        if (usdnBalance == 0) {
            return;
        }

        console2.log("bound wrap amount");
        usdnAmount = bound(usdnAmount, 0, usdnBalance);
        vm.prank(msg.sender);
        _usdn.approve(address(this), usdnAmount);

        vm.prank(msg.sender);
        this.wrap(usdnAmount);
    }

    function unwrapTest(uint256 wusdnAmount) external {
        uint256 wusdnBalance = balanceOf(msg.sender);
        if (wusdnBalance == 0) {
            return;
        }

        console2.log("bound unwrap amount");
        wusdnAmount = bound(wusdnAmount, 0, wusdnBalance);

        vm.prank(msg.sender);
        this.unwrap(wusdnAmount);
    }

    function transferTest(uint256 to, uint256 wusdnAmount) external {
        uint256 wusdnBalance = balanceOf(msg.sender);
        if (wusdnBalance == 0) {
            return;
        }

        console2.log("bound transfer amount");
        wusdnAmount = bound(wusdnAmount, 1, wusdnBalance);
        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);

        vm.prank(msg.sender);
        this.transfer(_actors[to], wusdnAmount);
    }

    function usdnTransferTest(uint256 to, uint256 value) external {
        uint256 usdnBalance = _usdn.balanceOf(msg.sender);
        if (usdnBalance == 0) {
            return;
        }

        console2.log("bound transfer value");
        value = bound(value, 1, usdnBalance);
        console2.log("bound to address");
        to = bound(to, 0, _actors.length - 1);

        vm.prank(msg.sender);
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

        _usdn.mint(msg.sender, usdnAmount);
    }

    function usdnBurnTest(uint256 usdnAmount) external {
        uint256 usdnBalance = _usdn.balanceOf(msg.sender);
        if (usdnBalance == 0) {
            return;
        }

        console2.log("bound burn value");
        usdnAmount = bound(usdnAmount, 1, usdnBalance);

        vm.prank(msg.sender);
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

        _usdn.rebase(newDivisor);
    }
}
