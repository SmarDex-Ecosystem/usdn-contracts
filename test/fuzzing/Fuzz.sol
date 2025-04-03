// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { FuzzGuided } from "./FuzzGuided.sol";

contract Fuzz is FuzzGuided {
    constructor() payable {
        vm.warp(1_524_785_992); //echidna starting time

        setup(address(this));
    }
}
