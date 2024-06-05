// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IWstETH is IERC20Metadata, IERC20Permit {
    /**
     * @notice Exchanges stETH to wstETH
     * @param _stETHAmount The amount of stETH to wrap in exchange for wstETH
     * @dev Requirements:
     *  - `_stETHAmount` must be non-zero
     *  - msg.sender must approve at least `_stETHAmount` stETH to this contract
     *  - msg.sender must have at least `_stETHAmount` of stETH
     * User should first approve `_stETHAmount` to the WstETH contract
     * @return Amount of wstETH user receives after wrap
     */
    function wrap(uint256 _stETHAmount) external returns (uint256);

    /**
     * @notice Exchanges wstETH to stETH
     * @param _wstETHAmount The amount of wstETH to unwrap in exchange for stETH
     * @dev Requirements:
     *  - `_wstETHAmount` must be non-zero
     *  - msg.sender must have at least `_wstETHAmount` wstETH
     * @return The amount of stETH user receives after unwrap
     */
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    /**
     * @notice Get the amount of wstETH for a given amount of stETH
     * @param _stETHAmount The amount of stETH
     * @return The amount of wstETH for a given stETH amount
     */
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    /**
     * @notice Get the amount of stETH for a given amount of wstETH
     * @param _wstETHAmount The amount of wstETH
     * @return The amount of stETH for a given wstETH amount
     */
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);

    /**
     * @notice Get the amount of stETH for a one wstETH
     * @return The amount of stETH for 1 wstETH
     */
    function stEthPerToken() external view returns (uint256);

    /**
     * @notice Get the amount of wstETH for a one stETH
     * @return The amount of wstETH for a 1 stETH
     */
    function tokensPerStEth() external view returns (uint256);

    /**
     * @notice Get the address of stETH
     * @return The address of stETH
     */
    function stETH() external view returns (address);
}
