// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { EchidnaAssert } from "./models/EchidnaAssert.sol";

contract TestForkEchidna is Test {
    EchidnaAssert public echidna;

    address internal DEPLOYER;
    address internal ATTACKER;

    function setUp() public {
        echidna = new EchidnaAssert();
        DEPLOYER = echidna.DEPLOYER();
        ATTACKER = echidna.ATTACKER();
    }

    function test_canInitiateDeposit() public {
        vm.prank(DEPLOYER);
        echidna.initiateDeposit(0.1 ether, 0, 0);
    }
}
