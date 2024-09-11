// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IStETH } from "../interfaces/IStEth.sol";
import { IWstETH } from "../interfaces/IWstETH.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit, IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20, ERC4626, IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract WstETH is IWstETH, ERC4626, ERC20Permit, Ownable {
    string private constant NAME = "Mock Wrapped Staked Ether";
    string private constant SYMBOL = "wstETH";

    constructor(IStETH _underlyingAsset)
        ERC20(NAME, SYMBOL)
        ERC20Permit(NAME)
        Ownable(msg.sender)
        ERC4626(IERC20(_underlyingAsset))
    { }

    receive() external payable {
        if (msg.value != 0) {
            // should receive msg.value stETH
            IStETH(asset()).deposit{ value: msg.value }(msg.sender);

            // mint wstETH and sent them to msg.sender
            deposit(msg.value, msg.sender);
        }
    }

    /**
     * @inheritdoc IERC20Metadata
     * @dev This function must be overridden to fix a solidity compiler error
     * @return The number of decimals
     */
    function decimals() public view override(IERC20Metadata, ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    /**
     * @inheritdoc IERC20Permit
     * @dev This function must be overridden to fix a solidity compiler error
     */
    function nonces(address _owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(_owner);
    }

    function wrap(uint256 _stETHAmount) external returns (uint256) {
        return deposit(_stETHAmount, msg.sender);
    }

    function unwrap(uint256 _wstETHAmount) external returns (uint256) {
        return redeem(_wstETHAmount, msg.sender, msg.sender);
    }

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256) {
        return convertToShares(_stETHAmount);
    }

    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return convertToAssets(_wstETHAmount);
    }

    function stEthPerToken() public view returns (uint256) {
        return convertToAssets(1 ether);
    }

    function tokensPerStEth() external view returns (uint256) {
        return convertToShares(1 ether);
    }

    function stETH() external view returns (address) {
        return address(asset());
    }
}
