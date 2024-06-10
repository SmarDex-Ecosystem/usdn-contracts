// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { IWusdn } from "src/interfaces/Usdn/IWusdn.sol";

/**
 * @title WUSDN token contract
 * @notice The USDN token is a rebasing token that is inflating its users' balances periodically. To allow for
 * stable balances, the WUSDN token was created, a wrapped token of the USDN that is not inflating, but increasing in
 * value instead
 */
contract Wusdn is ERC20Permit, IWusdn {
    using SafeERC20 for IUsdn;

    /// @notice Token name
    string internal constant NAME = "Wrapped Ultimate Synthetic Delta Neutral";

    /// @notice Token symbol
    string internal constant SYMBOL = "WUSDN";

    IUsdn public immutable USDN;

    /// @notice The precision factor of the shares
    uint256 private immutable SHARES_PRECISION_FACTOR;

    /**
     * @notice Construct the WUSDN token
     * @param usdn The address of the USDN token
     */
    constructor(IUsdn usdn) ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        USDN = usdn;
        SHARES_PRECISION_FACTOR = USDN.MAX_DIVISOR();
    }

    // function wrap(uint256 usdnAmount, address receiver, address owner) external returns (uint256) {
    //     uint256 maxAssets = maxWithdraw(owner);
    //     if (usdnAmount > maxAssets) {
    //         // revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
    //     }

    //     uint256 shares = previewWrap(usdnAmount);
    //     _withdraw(_msgSender(), receiver, owner, usdnAmount, shares);

    //     return shares;
    // }

    function wrap(uint256 usdnAmount) external returns (uint256 wrappedAmount_) {
        // uint256 maxAssets = maxDeposit(receiver);
        // if (usdnAmount > maxAssets) {
        //     // revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        // }

        wrappedAmount_ = USDN.convertToShares(usdnAmount) / SHARES_PRECISION_FACTOR;
        USDN.transferSharesFrom(msg.sender, address(this), wrappedAmount_ * SHARES_PRECISION_FACTOR);

        _mint(msg.sender, wrappedAmount_);
    }

    function unwrap(uint256 wrappedAmount) external returns (uint256 usdnAmount_) {
        // uint256 maxShares = maxRedeem(owner);
        // if (shares > maxShares) {
        //     // revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        // }

        usdnAmount_ = USDN.convertToTokens(wrappedAmount * SHARES_PRECISION_FACTOR);
        USDN.transferShares(msg.sender, wrappedAmount * SHARES_PRECISION_FACTOR);

        _burn(msg.sender, wrappedAmount);
    }

    /// @inheritdoc ERC20
    function decimals() public view override(ERC20) returns (uint8) {
        return super.decimals();
    }

    function totalUsdn() public view returns (uint256) {
        return USDN.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares);
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return _convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    // function previewWrap(uint256 assets) public view returns (uint256 wrappedAmount_) {
    //     uint256 roundedUsdnShares = USDN.convertToShares(assets) / SHARES_PRECISION_FACTOR * SHARES_PRECISION_FACTOR;
    //     wrappedAmount_ = USDN.convertToTokens(roundedUsdnShares);
    // }

    // function previewUnwrap(uint256 wrappedAmount) public view returns (uint256 usdnAmount_) {
    //     uint256 roundedUsdnShares = USDN.convertToShares(assets) / SHARES_PRECISION_FACTOR * SHARES_PRECISION_FACTOR;
    //     wrappedAmount_ = USDN.convertToTokens(roundedUsdnShares);
    // }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares);
    }

    function _convertToShares(uint256 usdnAmount) internal view returns (uint256 roundedUsdnShares) {
        uint256 usdnShares = USDN.convertToShares(usdnAmount);
        roundedUsdnShares = usdnShares / SHARES_PRECISION_FACTOR * SHARES_PRECISION_FACTOR;
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256 usdnAmount) {
        uint256 usdnShares = shares * SHARES_PRECISION_FACTOR;
        usdnAmount = USDN.convertToTokens(usdnShares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        USDN.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
