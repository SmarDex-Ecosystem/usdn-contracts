// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FuzzActions } from "./functional/FuzzActions.sol";
import { FuzzActionsAdmin } from "./functional/FuzzActionsAdmin.sol";

contract FuzzingSuite is FuzzActions, FuzzActionsAdmin { }
