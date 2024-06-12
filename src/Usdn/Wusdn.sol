// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { IWusdn } from "src/interfaces/Usdn/IWusdn.sol";

/**
 * @title WUSDN token contract
 * @notice The USDN token is a rebasing token that is inflating its users' balances periodically. To allow for
 * stable balances, the WUSDN token was created, it is not inflating, but increasing in value instead
 */
contract Wusdn is ERC20Permit, IWusdn {
    /// @notice Token name
    string internal constant NAME = "Wrapped Ultimate Synthetic Delta Neutral";

    /// @notice Token symbol
    string internal constant SYMBOL = "WUSDN";

    /// @notice The ratio used between USDN shares and WUSDN amounts
    uint256 private immutable SHARES_RATIO;

    /// @inheritdoc IWusdn
    IUsdn public immutable USDN;

    /**
     * @notice Construct the WUSDN token
     * @param usdn The address of the USDN token
     */
    constructor(IUsdn usdn) ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        USDN = usdn;
        SHARES_RATIO = USDN.MAX_DIVISOR();
    }

    /* -------------------------------------------------------------------------- */
    /*                             external functions                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IWusdn
    function wrap(uint256 usdnAmount) external returns (uint256 wrappedAmount_) {
        wrappedAmount_ = _wrap(usdnAmount, msg.sender);
    }

    /// @inheritdoc IWusdn
    function wrap(uint256 usdnAmount, address to) external returns (uint256 wrappedAmount_) {
        wrappedAmount_ = _wrap(usdnAmount, to);
    }

    /// @inheritdoc IWusdn
    function unwrap(uint256 wusdnAmount) external returns (uint256 usdnAmount_) {
        usdnAmount_ = _unwrap(wusdnAmount, msg.sender);
    }

    /// @inheritdoc IWusdn
    function unwrap(uint256 wusdnAmount, address to) external returns (uint256 usdnAmount_) {
        usdnAmount_ = _unwrap(wusdnAmount, to);
    }

    /// @inheritdoc IWusdn
    function totalUsdnBalance() external view returns (uint256) {
        return USDN.balanceOf(address(this));
    }

    /// @inheritdoc IWusdn
    function totalUsdnShares() external view returns (uint256) {
        return USDN.sharesOf(address(this));
    }

    /// @inheritdoc IWusdn
    function previewUnwrap(uint256 wusdnAmount) external view returns (uint256 usdnAmount_) {
        usdnAmount_ = USDN.convertToTokens(wusdnAmount * SHARES_RATIO);
    }

    /* -------------------------------------------------------------------------- */
    /*                              public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IWusdn
    function previewWrap(uint256 usdnAmount) public view returns (uint256 wrappedAmount_) {
        wrappedAmount_ = USDN.convertToShares(usdnAmount) / SHARES_RATIO;
    }

    /**
     * @inheritdoc IERC20Permit
     * @dev This function must be overridden to fix a solidity compiler error
     */
    function nonces(address owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /* -------------------------------------------------------------------------- */
    /*                              private functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Internal function to wrap USDN into WUSDN
     * @dev The caller must have already approved the USDN contract to transfer the required amount of USDN
     * When calling this function, we always transfer from the `msg.sender`
     * @param usdnAmount The amount of USDN to wrap
     * @param to The address to receive the WUSDN
     * @return wrappedAmount_ The amount of WUSDN received
     */
    function _wrap(uint256 usdnAmount, address to) private returns (uint256 wrappedAmount_) {
        // we consecutively divide (in {previewWrap}) and multiply by `SHARES_RATIO`
        // to ensure that the transferred USDN shares are a multiple of `SHARES_RATIO`
        wrappedAmount_ = previewWrap(usdnAmount);

        _mint(to, wrappedAmount_);
        USDN.transferSharesFrom(msg.sender, address(this), wrappedAmount_ * SHARES_RATIO);

        emit Wrap(msg.sender, to, usdnAmount, wrappedAmount_);
    }

    /**
     * @notice Internal function to unwrap WUSDN into USDN
     * @dev When calling this function, we always burn WUSDN tokens from the `msg.sender`
     * @param wusdnAmount The amount of WUSDN to unwrap
     * @param to The address to receive the USDN
     * @return usdnAmount_ The amount of USDN received
     */
    function _unwrap(uint256 wusdnAmount, address to) private returns (uint256 usdnAmount_) {
        uint256 usdnShares = wusdnAmount * SHARES_RATIO;
        usdnAmount_ = USDN.convertToTokens(usdnShares);
        _burn(msg.sender, wusdnAmount);

        USDN.transferShares(to, usdnShares);
        emit Unwrap(msg.sender, to, wusdnAmount, usdnAmount_);
    }
}
