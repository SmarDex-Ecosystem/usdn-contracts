// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IWusdn is IERC20, IERC20Permit, IERC4626 { }
