// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @notice This interface can be implemented by contracts that wish to transfer tokens during initiates
 * functions
 * @dev The contract must implement the ERC-165 interface detection mechanism
 */
interface IRouterFallback is IERC165 {
    /**
     * @notice Callback function to be called during initiate functions to transfer asset tokens
     * @param asset The asset token to transfer
     * @param _amount The amount of tokens to transfer
     */
    function transferAssetCallback(IERC20Metadata asset, uint256 _amount) external;

    /**
     * @notice Callback function to be called during initiate functions to transfer Sdex tokens
     * @param sdex The Sdex token to transfer
     * @param _amount The amount of Sdex tokens to transfer
     */
    function transferSdexCallback(IERC20Metadata sdex, uint256 _amount) external;
}
