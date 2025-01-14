// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title Interface For The Fee Collector Callback
 * @dev The contract must implement the ERC-165 interface detection mechanism.
 */
interface IFeeCollectorCallback is IERC165 {
    /**
     * @notice Function called by the protocol to notify the fee collector that a fee has been collected.
     * @param feeAmount The amount of fee collected.
     */
    function feeCollectorCallback(uint256 feeAmount) external;
}
