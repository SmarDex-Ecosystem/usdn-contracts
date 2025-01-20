// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { FuzzGuided } from "./FuzzGuided.sol";

contract Fuzz is FuzzGuided {
    constructor() payable {
        vm.warp(1_524_785_992); //echidna starting time

        setup(address(this));
    }

    function supportsInterface(bytes4) public pure returns (bool) {
        return true;
    }
}
