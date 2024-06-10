// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IWusdnEvents } from "src/interfaces/Usdn/IWusdnEvents.sol";

interface IWusdn is IWusdnEvents { }
// interface IWusdn is IERC20Permit, IWusdnEvents { }
