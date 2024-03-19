// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

/**
 * @title Wusdn token contract
 * @notice The Wusdn token is a wrapped token of the Ultimate Synthetic Delta Neutral (USDN) token.
 * Users can convert their USDN tokens to Wusdn tokens to use it with all protocols.
 */
contract Wusdn is ERC4626, ERC20Permit {
    using SafeERC20 for IUsdn;

    string internal constant NAME = "Wrapped Ultimate Synthetic Delta Neutral";
    string internal constant SYMBOL = "WUSDN";
    uint8 internal constant DECIMALS = 36;
    IUsdn private immutable _asset;

    constructor(IUsdn asset_) ERC20(NAME, SYMBOL) ERC4626(asset_) ERC20Permit(NAME) {
        _asset = asset_;
    }

    function decimals() public pure override(ERC20, ERC4626) returns (uint8) {
        return DECIMALS;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        return _asset.convertToShares(assets);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        return _asset.convertToTokens(shares);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _asset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
