// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @notice Interface for a fee collector contract to receive callbacks from the USDN protocol upon fee collection.
 * @dev Implementing contracts must support the ERC-165 interface detection mechanism.
 */
interface IFeeCollectorCallback is IERC165 {
    /**
     * @notice Called by the USDN protocol on the fee collector contract when the fee threshold is reached.
     * @param feeAmount The amount of the fee that was transferred to the fee collector.
     */
    function feeCollectorCallback(uint256 feeAmount) external;
}
