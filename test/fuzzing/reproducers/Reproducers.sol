// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { CurrentReproducers } from "./CurrentReproducers.sol";
import { ValidReproducers } from "./ValidReproducers.sol";

contract Reproducers is ValidReproducers, CurrentReproducers { }
