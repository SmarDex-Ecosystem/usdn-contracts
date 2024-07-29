// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "./Setup.sol";
import { FuzzActions } from "./functional/FuzzActions.sol";
import { FuzzSetup } from "./functional/FuzzSetup.sol";

contract FuzzingSuite is FuzzActions, FuzzSetup {
    constructor(bool isFuzzed) payable Setup(isFuzzed) { }
}
