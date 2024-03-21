// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { console2, Test } from "forge-std/Test.sol";

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

    function _deposit(address caller, address receiver, uint256 assets, uint256) internal override {
        uint256 sharesBefore = _asset.sharesOf(address(this));
        _asset.safeTransferFrom(caller, address(this), assets);
        uint256 mintShares = _asset.sharesOf(address(this)) - sharesBefore;
        _mint(receiver, mintShares);
        emit Deposit(caller, receiver, assets, mintShares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256) internal override {
        uint256 sharesBefore = _asset.sharesOf(address(this));
        _asset.safeTransfer(receiver, assets);
        uint256 burnShares = sharesBefore - _asset.sharesOf(address(this));
        if (caller != owner) {
            _spendAllowance(owner, caller, burnShares);
        }
        console2.log("assets", assets);
        console2.log("convertToShares", _asset.convertToShares(assets));
        console2.log("burnShares", burnShares);
        console2.log("owner", owner);
        console2.log("balanceOf(owner)", balanceOf(owner));
        _burn(owner, burnShares);
        emit Withdraw(caller, receiver, owner, assets, burnShares);
    }
}
