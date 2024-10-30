// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { IMultiMinter, MultiMinter } from "../../../src/utils/sepolia/MultiMinter.sol";

import { Sdex } from "../../../src/utils/sepolia/tokens/Sdex.sol";
import { StETH } from "../../../src/utils/sepolia/tokens/StETH.sol";
import { WstETH } from "../../../src/utils/sepolia/tokens/WstETH.sol";
import { USER_1 } from "../../utils/Constants.sol";

contract TestSepoliaMultiMint is Test {
    IMultiMinter internal multiMinter;
    StETH internal stETH;
    Sdex internal sdex;
    WstETH internal wstETH;

    function setUp() public {
        sdex = new Sdex();
        stETH = new StETH();
        wstETH = new WstETH(stETH);
        multiMinter = new MultiMinter(sdex, stETH, wstETH);
        sdex.transferOwnership(address(multiMinter));
        stETH.transferOwnership(address(multiMinter));
        wstETH.transferOwnership(address(multiMinter));
        multiMinter.acceptOwnershipOf(address(sdex));
        multiMinter.acceptOwnershipOf(address(stETH));
        multiMinter.acceptOwnershipOf(address(wstETH));
    }

    function test_mint() public {
        uint256 sdexBalanceBefore = sdex.balanceOf(USER_1);
        uint256 stEthBalanceBefore = stETH.balanceOf(USER_1);
        uint256 wstEthBalanceBefore = wstETH.balanceOf(USER_1);

        multiMinter.mint(USER_1, 1 ether, 2 ether, 3 ether);

        assertEq(sdex.balanceOf(USER_1), sdexBalanceBefore + 1 ether);
        assertEq(stETH.balanceOf(USER_1), stEthBalanceBefore + 2 ether);
        assertEq(wstETH.balanceOf(USER_1), wstEthBalanceBefore + 3 ether);
    }

    function test_aggregateOnlyOwner() public {
        uint256 sdexBalanceBefore = sdex.balanceOf(USER_1);
        uint256 wstEthBalanceBefore = wstETH.balanceOf(USER_1);
        uint256 stEthBalanceBefore = stETH.balanceOf(USER_1);

        IMultiMinter.Call[] memory calls = new IMultiMinter.Call[](3);
        calls[0] = (IMultiMinter.Call(address(sdex), abi.encodeWithSignature("mint(address,uint256)", USER_1, 1 ether)));
        calls[1] =
            (IMultiMinter.Call(address(wstETH), abi.encodeWithSignature("mint(address,uint256)", USER_1, 2 ether)));
        calls[2] =
            (IMultiMinter.Call(address(stETH), abi.encodeWithSignature("mint(address,uint256)", USER_1, 3 ether)));

        bytes[] memory returnData = multiMinter.aggregateOnlyOwner(calls);
        assertEq(returnData.length, 3);

        assertEq(sdex.balanceOf(USER_1), sdexBalanceBefore + 1 ether);
        assertEq(wstETH.balanceOf(USER_1), wstEthBalanceBefore + 2 ether);
        assertEq(stETH.balanceOf(USER_1), stEthBalanceBefore + 3 ether);
    }

    function test_setStEthPerWstEth() public {
        multiMinter.setStEthPerWstEth(0.42 ether);
        uint256 ratio = wstETH.stEthPerToken();
        assertEq(ratio, 0.42 ether);
    }

    function test_sweep() public {
        vm.deal(address(multiMinter), 1 ether);
        vm.deal(address(stETH), 1 ether);
        vm.deal(address(wstETH), 1 ether);

        multiMinter.sweep(USER_1);

        assertEq(USER_1.balance, 3 ether);
    }
}
