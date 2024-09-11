// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IWstETH } from "./IWstETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IStETH is IERC20, IERC20Permit {
    /**
     * @notice Indicates that the setStEthPerToken failed because the new stETH per token value is too small
     * @param currentStEthPerToken The current amount of stETH per token
     * @param newStEthPerToken The new amount of stETH per token that is too small
     */
    error setStEthPerTokenTooSmall(uint256 currentStEthPerToken, uint256 newStEthPerToken);

    /**
     * @notice Set the amount of stETH per wstETH token (only for owner)
     * @param _stEthAmount The new amount of stETH per wstETH token
     * @param wstETH The wstETH contract
     * @return The new amount of stETH per token
     */
    function setStEthPerToken(uint256 _stEthAmount, IWstETH wstETH) external returns (uint256);

    /**
     * @notice Mint stETH (only for owner)
     * @param account The account to mint stETH to
     * @param amount The amount of stETH to mint
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Deposit ETH to mint stETH
     * @param account The account to mint stETH to
     */
    function deposit(address account) external payable;

    /**
     * @notice Sweep ETH from the contract (only for owner)
     * @param to The account to sweep ETH to
     */
    function sweep(address to) external;
}
