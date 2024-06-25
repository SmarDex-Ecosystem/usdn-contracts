// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

interface IHevm {
    function warp(uint256 newTimestamp) external;

    function deal(address usr, uint256 amt) external;

    function roll(uint256 newNumber) external;

    function load(address where, bytes32 slot) external returns (bytes32);

    function store(address where, bytes32 slot, bytes32 value) external;

    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 r, bytes32 v, bytes32 s);

    function addr(uint256 privateKey) external returns (address add);

    function ffi(string[] calldata inputs) external returns (bytes memory result);

    function prank(address newSender) external;
}

contract Setup is Test {
    IHevm public hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address public DEPLOYER = address(0x10000);
    address public ATTACKER = address(0x20000);

    constructor() payable { }
}

contract EchidnaAssert is Setup {
/* -------------------------------------------------------------------------- */
/*                             Utils                                          */
/* -------------------------------------------------------------------------- */
}
