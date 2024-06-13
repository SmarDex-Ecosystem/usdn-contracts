// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IWusdn is IERC20Permit, IERC4626 { }
