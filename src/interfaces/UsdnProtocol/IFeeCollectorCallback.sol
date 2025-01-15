// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @notice This interface can be implemented by the fee collector contract to receive a callback from the USDN protocol.
 * @dev The contract must implement the ERC-165 interface detection mechanism.
 */
interface IFeeCollectorCallback is IERC165 {
    /**
     * @notice This function is called by the USDN protocol on the fee collector contract when the fee threshold is
     * reached, after the fee is sent to the fee collector.
     * @param feeAmount The fee amount that was sent to the fee collector.
     */
    function feeCollectorCallback(uint256 feeAmount) external;
}
