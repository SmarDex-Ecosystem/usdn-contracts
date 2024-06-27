// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { EchidnaAssert } from "./models/EchidnaAssert.sol";

contract TestForkEchidna is Test {
    EchidnaAssert public echidna;

    address internal DEPLOYER = address(0x10000);
    address internal ATTACKER = address(0x20000);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        echidna = new EchidnaAssert();
    }

    function test_ForkCanRun() public { }
}
