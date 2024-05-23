// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStETH is IERC20Metadata {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}
