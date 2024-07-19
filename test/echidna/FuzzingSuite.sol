// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FuzzActions } from "./functional/FuzzActions.sol";
import { FuzzActionsRebalancer } from "./functional/FuzzActionsRebalancer.sol";

contract FuzzingSuite is FuzzActions, FuzzActionsRebalancer { }
