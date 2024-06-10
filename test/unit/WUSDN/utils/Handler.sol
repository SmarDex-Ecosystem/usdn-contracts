// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2, Test } from "forge-std/Test.sol";

import { Usdn } from "src/Usdn/Usdn.sol";
import { Wusdn } from "src/Usdn/Wusdn.sol";

/**
 * @title WusdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract WusdnHandler is Wusdn, Test {
    Usdn public _usdn;

    constructor(Usdn usdn) Wusdn(usdn) {
        _usdn = usdn;
    }

    /* ------------------ Functions used for invariant testing ------------------ */

    function depositTest(uint256 assets) external {
        if (_usdn.balanceOf(msg.sender) == 0) {
            return;
        }
        console2.log("bound deposit amount");
        assets = bound(assets, 0, _usdn.balanceOf(msg.sender));
        vm.prank(msg.sender);
        _usdn.approve(address(this), type(uint256).max);

        vm.prank(msg.sender);
        this.wrap(assets);
    }

    function withdrawTest(uint256 assets) external {
        if (balanceOf(msg.sender) == 0) {
            return;
        }
        uint256 maxAssets = convertToAssets(balanceOf(msg.sender));
        console2.log("bound withdraw amount");
        assets = bound(assets, 0, maxAssets);

        vm.prank(msg.sender);
        this.unwrap(assets);
    }

    function transferTest(address to, uint256 shares) external {
        if (balanceOf(msg.sender) == 0 || to == address(0)) {
            return;
        }
        console2.log("bound transfer amount");
        shares = bound(shares, 1, balanceOf(msg.sender));

        vm.prank(msg.sender);
        this.transfer(to, shares);
    }

    function usdnTransferTest(address to, uint256 value) external {
        if (_usdn.balanceOf(msg.sender) == 0 || to == address(0)) {
            return;
        }
        console2.log("bound transfer value");
        value = bound(value, 1, _usdn.balanceOf(msg.sender));

        vm.prank(msg.sender);
        _usdn.transfer(to, value);
    }

    function usdnMintTest(uint256 value) external {
        uint256 maxTokens = _usdn.maxTokens();
        uint256 totalSupply = _usdn.totalSupply();

        if (totalSupply >= maxTokens - 1) {
            return;
        }

        console2.log("bound mint value");
        value = bound(value, 1, maxTokens - totalSupply - 1);

        _usdn.mint(msg.sender, value);
    }

    function usdnBurnTest(uint256 value) external {
        if (balanceOf(msg.sender) == 0) {
            return;
        }
        console2.log("bound burn value");
        value = bound(value, 1, balanceOf(msg.sender));

        vm.prank(msg.sender);
        _usdn.burn(value);
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
