// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console } from "forge-std/console.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IWstETH } from "../../src/interfaces/IWstETH.sol";

contract WstETH is ERC20, ERC20Permit, IWstETH {
    uint8 private testDecimals;
    uint256 private _stEthPerToken = 1.15 ether;
    bool private _reentrant;

    constructor() ERC20("Wrapped liquid staked Ether 2.0", "wstETH") ERC20Permit("Wrapped liquid staked Ether 2.0") {
        uint8 tokenDecimals = super.decimals();
        _mint(msg.sender, 4_000_000 * 10 ** tokenDecimals);
        testDecimals = tokenDecimals;
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

    /// @dev Receive ETH and mint wstETH
    receive() external payable {
        _mint(msg.sender, getWstETHByStETH(msg.value));
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

    /// @dev Whether to try to perform a reentrant call during transfers
    function setReentrant(bool reentrant) external {
        _reentrant = reentrant;
    }

    /// @dev Needed for interface compatibility
    function stETH() external pure returns (address) { }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (_reentrant) {
            (bool success,) = msg.sender.call(abi.encodeWithSignature("resetDepositAssets()"));
            if (!success) {
                // forward revert reason to the caller
                assembly {
                    let ptr := mload(0x40)
                    let size := returndatasize()
                    returndatacopy(ptr, 0, size)
                    revert(ptr, size)
                }
            }
        }
    }
}
