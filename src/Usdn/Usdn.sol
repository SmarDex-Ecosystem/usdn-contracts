// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IRebaseCallback } from "../interfaces/Usdn/IRebaseCallback.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";

/**
 * @title USDN token contract
 * @notice The USDN token supports the USDN Protocol and is minted when assets are deposited or withdrawn from the
 * vault and tokens are burned. The total supply and balances are increased periodically by adjusting a global divisor,
 * so that the price of the token doesn't grow too far past 1 USD
 *
 * @dev Base implementation of the ERC-20 interface by OpenZeppelin, adapted to support growable balances
 *
 * Unlike a normal ERC-20, we record balances as a number of shares. The balance is then computed by dividing the
 * shares by a divisor. This allows us to grow the total supply without having to update all balances
 *
 * Balances and total supply can only grow over time and never shrink
 */
contract Usdn is IUsdn, ERC20Permit, ERC20Burnable, AccessControl {
    /**
     * @dev Control the rounding when converting from shares to tokens
     * @param Down Round down (towards zero)
     * @param Closest Round towards the closest integer (0.5 rounds up)
     * @param Up Round up (towards positive infinity)
     */
    enum Rounding {
        Down,
        Closest,
        Up
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @inheritdoc IUsdn
    bytes32 public constant REBASER_ROLE = keccak256("REBASER_ROLE");

    /// @inheritdoc IUsdn
    uint256 public constant MAX_DIVISOR = 1e18;

    /// @inheritdoc IUsdn
    uint256 public constant MIN_DIVISOR = 1e9;

    /// @notice USDN token name
    string internal constant NAME = "Ultimate Synthetic Delta Neutral";

    /// @notice USDN token symbol
    string internal constant SYMBOL = "USDN";

    /* -------------------------------------------------------------------------- */
    /*                              Storage variables                             */
    /* -------------------------------------------------------------------------- */

    /// @notice Mapping from account to number of shares
    mapping(address account => uint256) internal _shares;

    /// @notice Sum of all the shares
    uint256 internal _totalShares;

    /// @notice Divisor used to convert between shares and tokens
    uint256 internal _divisor = MAX_DIVISOR;

    /// @notice A contract that will be called whenever a rebase happens
    IRebaseCallback internal _rebaseHandler;

    /**
     * @notice Create an instance of the USDN token
     * @param minter Address which should have the minter role by default (zero address to skip)
     * @param rebaser Address which should have the rebaser role by default (zero address to skip)
     */
    constructor(address minter, address rebaser) ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (minter != address(0)) {
            _grantRole(MINTER_ROLE, minter);
        }
        if (rebaser != address(0)) {
            _grantRole(REBASER_ROLE, rebaser);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 view functions                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IERC20
     * @dev This function does not return the sum of all token balances and is based on the shares to token ratio
     * Please use {totalShares} for an accurate total supply
     */
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return _convertToTokens(_totalShares, Rounding.Closest, _divisor);
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return _convertToTokens(sharesOf(account), Rounding.Closest, _divisor);
    }

    /**
     * @inheritdoc IERC20Permit
     * @dev This function must be overridden to fix a solidity compiler error
     */
    function nonces(address owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 base functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function burn(uint256 amount) public override(ERC20Burnable, IUsdn) {
        super.burn(amount);
    }

    /// @inheritdoc IUsdn
    function burnFrom(address account, uint256 amount) public override(ERC20Burnable, IUsdn) {
        super.burnFrom(account, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Special token functions                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function sharesOf(address account) public view returns (uint256) {
        return _shares[account];
    }

    /// @inheritdoc IUsdn
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    /// @inheritdoc IUsdn
    function convertToTokens(uint256 amountShares) external view returns (uint256 tokens_) {
        tokens_ = _convertToTokens(amountShares, Rounding.Closest, _divisor);
    }

    /// @inheritdoc IUsdn
    function convertToTokensRoundUp(uint256 amountShares) external view returns (uint256 tokens_) {
        tokens_ = _convertToTokens(amountShares, Rounding.Up, _divisor);
    }

    /// @inheritdoc IUsdn
    function convertToShares(uint256 amountTokens) public view returns (uint256 shares_) {
        if (amountTokens > maxTokens()) {
            revert UsdnMaxTokensExceeded(amountTokens);
        }
        shares_ = amountTokens * _divisor;
    }

    /// @inheritdoc IUsdn
    function divisor() external view returns (uint256) {
        return _divisor;
    }

    /// @inheritdoc IUsdn
    function rebaseHandler() external view returns (IRebaseCallback) {
        return _rebaseHandler;
    }

    /// @inheritdoc IUsdn
    function maxTokens() public view returns (uint256) {
        return type(uint256).max / _divisor;
    }

    /// @inheritdoc IUsdn
    function transferShares(address to, uint256 value) external returns (bool) {
        address owner = _msgSender();
        _transferShares(owner, to, value, _convertToTokens(value, Rounding.Closest, _divisor));
        return true;
    }

    /// @inheritdoc IUsdn
    function transferSharesFrom(address from, address to, uint256 value) external returns (bool) {
        address spender = _msgSender();
        uint256 d = _divisor;
        // to make sure we spend 1 wei of allowance in case the number of shares is less than 1 wei of tokens,
        // we round up
        _spendAllowance(from, spender, _convertToTokens(value, Rounding.Up, d));
        // the amount of tokens below is only used for emitting an event, we round to the closest value
        _transferShares(from, to, value, _convertToTokens(value, Rounding.Closest, d));
        return true;
    }

    /// @inheritdoc IUsdn
    function burnShares(uint256 value) external {
        _burnShares(_msgSender(), value, _convertToTokens(value, Rounding.Closest, _divisor));
    }

    /// @inheritdoc IUsdn
    function burnSharesFrom(address account, uint256 value) public {
        uint256 d = _divisor;
        // to make sure we spend 1 wei of allowance in case the number of shares is less than 1 wei of tokens,
        // we round up
        _spendAllowance(account, _msgSender(), _convertToTokens(value, Rounding.Up, d));
        // the amount of tokens below is only used for emitting an event, we round to the closest value
        _burnShares(account, value, _convertToTokens(value, Rounding.Closest, d));
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @inheritdoc IUsdn
    function mintShares(address to, uint256 amount) external onlyRole(MINTER_ROLE) returns (uint256 mintedTokens_) {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        mintedTokens_ = _convertToTokens(amount, Rounding.Closest, _divisor);
        _updateShares(address(0), to, amount, mintedTokens_);
    }

    /// @inheritdoc IUsdn
    function rebase(uint256 newDivisor)
        external
        onlyRole(REBASER_ROLE)
        returns (bool rebased_, uint256 oldDivisor_, bytes memory callbackResult_)
    {
        oldDivisor_ = _divisor;
        if (newDivisor > oldDivisor_) {
            // divisor can only be decreased
            newDivisor = oldDivisor_;
        } else if (newDivisor < MIN_DIVISOR) {
            // divisor cannot be lower than `MIN_DIVISOR`
            newDivisor = MIN_DIVISOR;
        }
        if (newDivisor == oldDivisor_) {
            // no rebase necessary
            return (false, oldDivisor_, callbackResult_);
        }

        _divisor = newDivisor;
        rebased_ = true;
        IRebaseCallback handler = _rebaseHandler;
        if (address(handler) != address(0)) {
            callbackResult_ = handler.rebaseCallback(oldDivisor_, newDivisor);
        }
        emit Rebase(oldDivisor_, newDivisor);
    }

    /// @inheritdoc IUsdn
    function setRebaseHandler(IRebaseCallback newHandler) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _rebaseHandler = newHandler;
        emit RebaseHandlerUpdated(newHandler);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Convert an amount of shares into the corresponding amount of tokens, rounding the division according to
     * `rounding`
     * @dev The conversion never overflows as we are performing a division
     * If rounding to the nearest integer and the result is exactly at the halfway point, we round up
     * @param amountShares The amount of shares to convert to tokens
     * @param rounding Whether to round towards zero, the closest integer, or positive infinity
     * @param d Current value of the divisor
     * @return tokens_ The corresponding amount of tokens
     */
    function _convertToTokens(uint256 amountShares, Rounding rounding, uint256 d)
        internal
        pure
        returns (uint256 tokens_)
    {
        if (d <= 1) {
            // this should never happen, but the check allows to perform unchecked math below
            revert UsdnInvalidDivisor();
        }
        unchecked {
            // division & modulo can't error because d > 0
            uint256 tokensDown = amountShares / d;
            uint256 remainder = amountShares % d;
            if (rounding == Rounding.Down || remainder == 0) {
                // if we want to round down, or there is no remainder to the division, we can return the result
                return tokensDown;
            }

            // division can't error because d > 0
            if (tokensDown == type(uint256).max / d) {
                // early return, we can't have a token amount larger than maxTokens() = uint256.max / _divisor
                return tokensDown;
            }
            uint256 tokensUp = tokensDown + 1; // this can't overflow because d > 1
            if (rounding == Rounding.Up) {
                // we know there is a remainder to the division, so this value is the result of rounding up the quotient
                return tokensUp;
            }

            // below, we round to the closest integer
            uint256 half = FixedPointMathLib.divUp(d, 2); // need to divUp so some edge cases round correctly
            // if the remainder is equal to or larger than half of the divisor, we round up, else down
            if (remainder >= half) {
                tokens_ = tokensUp;
            } else {
                tokens_ = tokensDown;
            }
        }
    }

    /**
     * @notice Transfer some shares from `from` to `to`
     * @dev Reverts if `from` or `to` is the zero address
     * @param from The source address
     * @param to The destination address
     * @param value The amount of shares to transfer
     * @param tokenValue The converted amount in tokens, for inclusion in the `Transfer` event
     */
    function _transferShares(address from, address to, uint256 value, uint256 tokenValue) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _updateShares(from, to, value, tokenValue);
    }

    /**
     * @notice Burn shares from `account`
     * @dev Reverts if the account is the zero address
     * @param account The owner of the shares
     * @param value The number of shares to burn
     * @param tokenValue The converted value in tokens, for emitting the `Transfer` event
     */
    function _burnShares(address account, uint256 value, uint256 tokenValue) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _updateShares(account, address(0), value, tokenValue);
    }

    /**
     * @notice Transfer a `value` amount of shares from `from` to `to`, or mint (or burn) if `from` or `to`
     * is the zero address
     * @dev Emits a {Transfer} event
     * @param from The source address
     * @param to The destination address
     * @param value The number of shares to transfer
     * @param tokenValue The value converted to tokens, for inclusion in the `Transfer` event
     */
    function _updateShares(address from, address to, uint256 value, uint256 tokenValue) internal {
        if (from == address(0)) {
            // overflow check required: The rest of the code assumes that `totalShares` never overflows
            _totalShares += value;
        } else {
            uint256 fromBalance = _shares[from];
            if (fromBalance < value) {
                revert UsdnInsufficientSharesBalance(from, fromBalance, value);
            }
            unchecked {
                // overflow not possible: value <= fromBalance <= totalShares
                _shares[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // overflow not possible: value <= totalShares or value <= fromBalance <= totalShares
                _totalShares -= value;
            }
        } else {
            unchecked {
                // overflow not possible: balance + value is at most `totalShares`, which we know fits into a uint256
                _shares[to] += value;
            }
        }

        emit Transfer(from, to, tokenValue);
    }

    /**
     * @inheritdoc ERC20
     * @notice Transfer a `value` amount of tokens from `from` to `to`, or mint (or burn) if `from` or `to`
     * is the zero address
     * @dev Emits a {Transfer} event
     * @param from The source address
     * @param to The destination address
     * @param value The amount of tokens to transfer, is internally converted to shares
     */
    function _update(address from, address to, uint256 value) internal override {
        // convert the value to shares, reverts with `UsdnMaxTokensExceeded()` if value is too high
        uint256 valueShares = convertToShares(value);
        uint256 fromBalance = balanceOf(from);

        if (from == address(0)) {
            // overflow check required: the rest of the code assumes that `totalShares` never overflows
            _totalShares += valueShares;
        } else {
            uint256 fromShares = _shares[from];
            // perform the balance check on the amount of tokens, since due to rounding errors, `valueShares` can be
            // slightly larger than `fromShares`
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            if (valueShares <= fromShares) {
                // since valueShares <= fromShares, we can safely subtract `valueShares` from `fromShares`
                unchecked {
                    _shares[from] -= valueShares;
                }
            } else {
                // due to a rounding error, valueShares can be slightly larger than fromShares. In this case, we
                // simply set the balance to zero and adjust the transferred amount of shares
                _shares[from] = 0;
                valueShares = fromShares;
            }
        }

        if (to == address(0)) {
            // burn: Since valueShares <= fromShares <= totalShares, we can safely subtract `valueShares` from
            // `totalShares`
            unchecked {
                _totalShares -= valueShares;
            }
        } else {
            // since shares + valueShares <= totalShares, we can safely add `valueShares` to the user shares
            unchecked {
                _shares[to] += valueShares;
            }
        }

        emit Transfer(from, to, value);
    }
}
