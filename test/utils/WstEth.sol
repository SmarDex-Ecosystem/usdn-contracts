// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IWstETH } from "../../src/interfaces/IWstETH.sol";

contract WstETH is ERC20, ERC20Permit, IWstETH {
    uint8 private testDecimals;
    /// @dev Returns the amount of ETH per stETH (mock value)
    uint256 public stEthPerToken;

    constructor() ERC20("Wrapped liquid staked Ether 2.0", "wstETH") ERC20Permit("Wrapped liquid staked Ether 2.0") {
        uint8 tokenDecimals = super.decimals();
        _mint(msg.sender, 4_000_000 * 10 ** tokenDecimals);
        testDecimals = tokenDecimals;
        stEthPerToken = 1.15 ether;
    }

    /// @dev Mint wstETH to the specified address
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Mint wstETH to the specified address and approve the spender
    function mintAndApprove(address to, uint256 amount, address spender, uint256 value) external {
        _mint(to, amount);
        _approve(to, spender, value);
    }

    function tokensPerStEth() public view returns (uint256) {
        return 1 ether / stEthPerToken;
    }

    function setStEthPerToken(uint256 newTokensPerStEth) external {
        require(newTokensPerStEth > 0, "WstETH: invalid tokens per stETH");
        stEthPerToken = newTokensPerStEth;
    }

    /// @dev Returns the amount of wstETH per stETH (mock value)
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256) {
        return _stETHAmount * stEthPerToken / 1 ether;
    }

    /// @dev Returns the amount of stETH per wstETH (mock value)
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return _wstETHAmount * 1 ether / stEthPerToken;
    }

    /// @dev Receive ETH and mint wstETH
    receive() external payable {
        _mint(msg.sender, msg.value * 1 ether / stEthPerToken);
    }

    /// @dev Needed for interface compatibility
    function nonces(address) public pure override(ERC20Permit, IERC20Permit) returns (uint256) {
        return 0;
    }

    /// @dev Needed for interface compatibility
    function wrap(uint256) external returns (uint256) { }

    /// @dev Needed for interface compatibility
    function unwrap(uint256) external returns (uint256) { }

    function setDecimals(uint8 newDecimals) external {
        testDecimals = newDecimals;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return testDecimals;
    }

    /// @dev Needed for interface compatibility
    function stETH() external pure returns (address) { }
}
