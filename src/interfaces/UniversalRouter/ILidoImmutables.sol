// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ILidoImmutables {
    /**
     * @notice Getter for the address of the steth token
     * @return The address of the steth token
     */
    function STETH() external view returns (IERC20Metadata);
}
