// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IWstETH } from "./IWstETH.sol";

interface IStETH is IERC20, IERC20Permit {
    /**
     * @notice Gets the total amount of Ether controlled by the system
     * @return total balance in wei
     */
    function getTotalPooledEther() external view returns (uint256);

    /**
     * @notice Set the amount of stETH per wstETH token (only for owner)
     * @param stEthAmount The new amount of stETH per wstETH token
     * @param wstETH The wstETH contract
     * @return The new amount of stETH per token
     */
    function setStEthPerToken(uint256 stEthAmount, IWstETH wstETH) external returns (uint256);

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
    function submit(address account) external payable;

    /**
     * @notice Sweep ETH from the contract (only for owner)
     * @param to The account to sweep ETH to
     */
    function sweep(address payable to) external;
}
