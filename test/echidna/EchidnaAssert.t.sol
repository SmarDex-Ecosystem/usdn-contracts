// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { EchidnaAssert } from "../src/echidna/EchidnaAssert.sol";

import "forge-std/Test.sol";

contract TestEchidna is Test {
    EchidnaAssert public echidna;

    address internal DEPLOYER = address(0x10000);
    address internal ATTACKER = address(0x20000);

    function setUp() public {
        echidna = new EchidnaAssert();
    }

    function test_canRun() public { }
}
