// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FuzzActions } from "./functional/FuzzActions.sol";
import { FuzzActionsAdmin } from "./functional/FuzzActionsAdmin.sol";
import { FuzzActionsRebalancer } from "./functional/FuzzActionsRebalancer.sol";
import { FuzzSetup } from "./functional/FuzzSetup.sol";
import { FuzzTransfer } from "./functional/FuzzTransfer.sol";

contract FuzzingSuite is FuzzActions, FuzzActionsRebalancer, FuzzSetup, FuzzActionsAdmin, FuzzTransfer { }
