// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

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
     * @notice Needed for router
     * @return stETH_ The stETH address
     */
    function stETH() external pure returns (address stETH_) {
        return stETH_;
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
    function getWstETHByStETH(uint256 _stETHAmount) public view returns (uint256) {
        return _stETHAmount * 1 ether / _stEthPerToken;
    }

    /**
     * @notice Get amount of stETH for a given amount of wstETH
     * @param _wstETHAmount amount of wstETH
     * @return Amount of stETH for a given wstETH amount
     */
    function getStETHByWstETH(uint256 _wstETHAmount) public view returns (uint256) {
        return _wstETHAmount * _stEthPerToken / 1 ether;
    }

    /**
     * @notice Exchanges wstETH to ETH
     * @param _wstETHAmount amount of wstETH to unwrap in exchange for ETH
     * @dev LIDO does not allow an instant withdrawal in ETH, this is for test purposes
     * Requirements:
     *  - `_wstETHAmount` must be non-zero
     *  - `address(this).balance` must be superior or equal to getStETHByWstETH(_wstETHAmount)
     *  - msg.sender must have at least `_wstETHAmount` wstETH.
     * @return Amount of ETH user receives after unwrap
     */
    function withdraw(uint256 _wstETHAmount) external returns (uint256) {
        require(_wstETHAmount > 0, "wstETH: zero amount unwrap not allowed");

        uint256 ethAmount = getStETHByWstETH(_wstETHAmount);
        require(address(this).balance >= ethAmount, "wstETH: not enough balance");

        _burn(msg.sender, _wstETHAmount);
        (bool success,) = msg.sender.call{ value: ethAmount }("");
        require(success, "wstETH: ETH transfer failed");

        return ethAmount;
    }

    /**
     * @notice Withdraw the ether from the contract
     * @dev To avoid loosing of the ETH after the tests
     */
    function sweep() external onlyOwner {
        (bool success,) = msg.sender.call{ value: address(this).balance }("");
        require(success, "wstETH: ETH transfer failed");
    }

    receive() external payable {
        _mint(msg.sender, getWstETHByStETH(msg.value));
    }
}
