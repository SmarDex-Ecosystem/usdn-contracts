// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Permit, IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20, ERC4626, IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { IStETH } from "../interfaces/IStETH.sol";
import { IWstETH } from "../interfaces/IWstETH.sol";

contract MockWstETH is IWstETH, ERC4626, ERC20Permit, Ownable {
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
            // need to do that before minting stETH. Otherwise, the totalAsset() will be incorrect. And so, a standard
            // call to deposit() will be incorrect.
            uint256 wstETHAmount = previewDeposit(msg.value);

            // should receive msg.value stETH
            IStETH(asset()).submit{ value: msg.value }(address(this));

            // mint wstETH and sent them to msg.sender
            _mint(msg.sender, wstETHAmount);

            emit Deposit(msg.sender, msg.sender, msg.value, wstETHAmount);
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
    function nonces(address owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc IWstETH
    function wrap(uint256 stETHAmount) external returns (uint256) {
        return deposit(stETHAmount, msg.sender);
    }

    /// @inheritdoc IWstETH
    function unwrap(uint256 wstETHAmount) external returns (uint256) {
        return redeem(wstETHAmount, msg.sender, msg.sender);
    }

    /// @inheritdoc IWstETH
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256) {
        return convertToShares(stETHAmount);
    }

    /// @inheritdoc IWstETH
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256) {
        return convertToAssets(wstETHAmount);
    }

    /// @inheritdoc IWstETH
    function stEthPerToken() public view returns (uint256) {
        return convertToAssets(1 ether);
    }

    /// @inheritdoc IWstETH
    function tokensPerStEth() external view returns (uint256) {
        return convertToShares(1 ether);
    }

    /// @inheritdoc IWstETH
    function stETH() external view returns (address) {
        return address(asset());
    }
}
