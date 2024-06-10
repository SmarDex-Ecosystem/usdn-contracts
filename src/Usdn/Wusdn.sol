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

    function previewWrap(uint256 usdnAmount) public view returns (uint256 wrappedAmount_) {
        wrappedAmount_ = USDN.convertToShares(usdnAmount) / SHARES_PRECISION_FACTOR;
    }

    function wrap(uint256 usdnAmount) external returns (uint256 wrappedAmount_) {
        wrappedAmount_ = _wrap(usdnAmount, msg.sender);
    }

    function wrap(uint256 usdnAmount, address to) external returns (uint256 wrappedAmount_) {
        wrappedAmount_ = _wrap(usdnAmount, to);
    }

    function _wrap(uint256 usdnAmount, address to) internal returns (uint256 wrappedAmount_) {
        wrappedAmount_ = previewWrap(usdnAmount);
        USDN.transferSharesFrom(msg.sender, address(this), wrappedAmount_ * SHARES_PRECISION_FACTOR);

        _mint(to, wrappedAmount_);
        // TO DO emit Wrap(from, to, usdnAmount, wrappedAmount_);
    }

    function wrapFrom(address from, uint256 usdnAmount, address to) external returns (uint256 wrappedAmount_) {
        wrappedAmount_ = previewWrap(usdnAmount);

        uint256 usdnShares = wrappedAmount_ * SHARES_PRECISION_FACTOR;
        USDN.transferSharesFrom(from, msg.sender, usdnShares);
        USDN.transferSharesFrom(msg.sender, address(this), usdnShares);

        _mint(to, wrappedAmount_);
    }

    function previewUnwrap(uint256 wrappedAmount) public view returns (uint256 usdnAmount_) {
        usdnAmount_ = USDN.convertToTokens(wrappedAmount * SHARES_PRECISION_FACTOR);
    }

    function unwrap(uint256 wrappedAmount) external returns (uint256 usdnAmount_) {
        usdnAmount_ = _unwrap(msg.sender, wrappedAmount, msg.sender);
    }

    function unwrap(uint256 wrappedAmount, address to) external returns (uint256 usdnAmount_) {
        usdnAmount_ = _unwrap(msg.sender, wrappedAmount, to);
    }

    function unwrapFrom(address from, uint256 wrappedAmount, address to) external returns (uint256 usdnAmount_) {
        uint256 usdnShares = wrappedAmount * SHARES_PRECISION_FACTOR;
        usdnAmount_ = USDN.convertToTokens(usdnShares);

        _spendAllowance(from, msg.sender, wrappedAmount);
        _burn(from, wrappedAmount);

        USDN.transferSharesFrom(address(this), to, usdnShares);
    }

    function _unwrap(address from, uint256 wrappedAmount, address to) internal returns (uint256 usdnAmount_) {
        uint256 usdnShares = wrappedAmount * SHARES_PRECISION_FACTOR;
        usdnAmount_ = USDN.convertToTokens(usdnShares);
        _burn(from, wrappedAmount);

        USDN.transferSharesFrom(address(this), to, usdnShares);
        // TO DO emit Unwrap(from, to, usdnAmount_, wrappedAmount);
    }

    function totalUsdn() external view returns (uint256) {
        return USDN.balanceOf(address(this));
    }
}
