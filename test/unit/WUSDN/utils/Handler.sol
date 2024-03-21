// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2, Test } from "forge-std/Test.sol";

import { Usdn } from "src/Usdn.sol";
import { Wusdn } from "src/Wusdn.sol";

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
        console2.log("bound deposit");
        if (_usdn.balanceOf(msg.sender) == 0) {
            return;
        }
        assets = bound(assets, 0, _usdn.balanceOf(msg.sender));
        vm.prank(msg.sender);
        _usdn.approve(address(this), type(uint256).max);

        deposit(assets, msg.sender);
    }

    function mintTest(uint256 shares) external {
        console2.log("bound deposit");
        if (_usdn.balanceOf(msg.sender) == 0) {
            return;
        }
        uint256 maxShares = convertToShares(_usdn.balanceOf(msg.sender));
        shares = bound(shares, 0, maxShares);
        vm.prank(msg.sender);
        _usdn.approve(address(this), type(uint256).max);

        mint(shares, msg.sender);
    }

    function withdrawTest(uint256 assets) external {
        console2.log("bound withdraw");
        if (balanceOf(msg.sender) == 0) {
            return;
        }
        uint256 maxAssets = convertToAssets(balanceOf(msg.sender));
        assets = bound(assets, 0, maxAssets);

        withdraw(assets, msg.sender, msg.sender);
    }

    function redeemTest(uint256 shares) external {
        console2.log("bound withdraw");
        if (balanceOf(msg.sender) == 0) {
            return;
        }
        shares = bound(shares, 0, balanceOf(msg.sender));

        redeem(shares, msg.sender, msg.sender);
    }
}
