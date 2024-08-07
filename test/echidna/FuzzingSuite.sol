// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FuzzActions } from "./functional/FuzzActions.sol";
import { FuzzSetup } from "./functional/FuzzSetup.sol";

contract FuzzingSuite is FuzzActions, FuzzSetup { }
