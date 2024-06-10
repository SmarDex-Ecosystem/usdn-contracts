// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

/**
 * @title WUSDN token contract
 * @notice The USDN token is a rebasing token that is inflating its users' balances periodically. To allow for
 * stable balances, the WUSDN token was created, a wrapped token of the USDN that is not inflating, but increasing in
 * value instead
 */
contract Wusdn is ERC20Permit {
    using SafeERC20 for IUsdn;

    enum Rounding {
        Floor,
        Ceil
    }

    /// @notice Token name
    string internal constant NAME = "Wrapped Ultimate Synthetic Delta Neutral";

    /// @notice Token symbol
    string internal constant SYMBOL = "WUSDN";

    IUsdn public immutable USDN;

    /// @notice The precision factor of the shares
    uint256 private immutable SHARES_PRECISION_FACTOR;

    /**
     * @notice Construct the WUSDN token
     * @param asset The address of the USDN token
     */
    constructor(IERC20 asset) ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        USDN = IUsdn(address(asset));
        SHARES_PRECISION_FACTOR = USDN.MAX_DIVISOR();
    }

    function deposit(uint256 usdnAmount, address receiver) public returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (usdnAmount > maxAssets) {
            // revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(usdnAmount);
        _deposit(_msgSender(), receiver, usdnAmount, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            // revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    function withdraw(uint256 usdnAmount, address receiver, address owner) public returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (usdnAmount > maxAssets) {
            // revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(usdnAmount);
        _withdraw(_msgSender(), receiver, owner, usdnAmount, shares);

        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            // revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /// @inheritdoc ERC20
    function decimals() public view override(ERC20) returns (uint8) {
        return super.decimals();
    }

    function totalAssets() public view returns (uint256) {
        return USDN.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Rounding.Floor);
    }

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return _convertToAssets(balanceOf(owner), Rounding.Floor);
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Rounding.Floor);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Rounding.Floor);
    }

    function _convertToShares(uint256 usdnAmount, Rounding rounding) internal view returns (uint256 wrappedShares) {
        uint256 usdnShares = USDN.convertToShares(usdnAmount);
        wrappedShares = usdnShares / SHARES_PRECISION_FACTOR;
    }

    function _convertToAssets(uint256 shares, Rounding rounding) internal view returns (uint256 usdnAmount) {
        uint256 usdnShares = shares * SHARES_PRECISION_FACTOR;
        usdnAmount = USDN.convertToTokens(usdnShares);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal {
        USDN.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);

        // emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        USDN.safeTransfer(receiver, assets);

        // emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
