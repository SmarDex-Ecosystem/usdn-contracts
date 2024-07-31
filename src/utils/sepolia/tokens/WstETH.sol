// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract WstETH is ERC20Permit, Ownable {
    uint256 private _stEthPerToken = 1 ether;

    constructor()
        Ownable(msg.sender)
        ERC20Permit("Wrapped liquid staked Ether 2.0")
        ERC20("Wrapped liquid staked Ether 2.0", "wstETH")
    { }

    /**
     * @notice Mint `amount` tokens to `to`
     * @param to The address that will receive the tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Update the amount of stEth a WstEth token is worth
     * @dev The provided value cannot be 0
     * @param stEthAmount The new amount of stEth given for a WstEth token
     */
    function setStEthPerToken(uint256 stEthAmount) external onlyOwner {
        require(stEthAmount > 0, "Cannot be 0");

        _stEthPerToken = stEthAmount;
    }

    /**
     * @notice Get amount of stETH for a one wstETH
     * @return Amount of stETH for 1 wstETH
     */
    function stEthPerToken() external view returns (uint256) {
        return _stEthPerToken;
    }

    /**
     * @notice Get the amount of wstETH for one stETH token
     * @return Amount of wstETH for one stETH token
     */
    function tokensPerStEth() external view returns (uint256) {
        return 1e36 / _stEthPerToken;
    }

    /**
     * @notice Get amount of wstETH for a given amount of stETH
     * @param _stETHAmount amount of stETH
     * @return Amount of wstETH for a given stETH amount
     */
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256) {
        return _stETHAmount * _stEthPerToken / 1 ether;
    }

    /**
     * @notice Get amount of stETH for a given amount of wstETH
     * @param _wstETHAmount amount of wstETH
     * @return Amount of stETH for a given wstETH amount
     */
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return _wstETHAmount * 1 ether / _stEthPerToken;
    }
}
