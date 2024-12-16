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
 * @title USDN Token Contract
 * @notice The USDN token supports the USDN Protocol. It is minted when assets are deposited into the USDN Protocol
 * vault and burned when withdrawn. The total supply and individual balances are periodically increased by modifying a
 * global divisor, ensuring the token's value doesn't grow too far past 1 USD.
 * @dev This contract extends OpenZeppelin's ERC-20 implementation, adapted to support growable balances.
 * Unlike a traditional ERC-20, balances are stored as shares, which are converted into token amounts using the
 * global divisor. This design allows for supply growth without updating individual balances. Any divisor modification
 * can only make balances and total supply increase.
 */
contract Usdn is IUsdn, ERC20Permit, ERC20Burnable, AccessControl {
    /**
     * @dev Enum representing the rounding options when converting from shares to tokens.
     * @param Down Rounds down to the nearest integer (towards zero).
     * @param Closest Rounds to the nearest integer.
     * @param Up Rounds up to the nearest integer (towards positive infinity).
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

    /// @notice The name of the USDN token.
    string internal constant NAME = "Ultimate Synthetic Delta Neutral";

    /// @notice The symbol of the USDN token.
    string internal constant SYMBOL = "USDN";

    /* -------------------------------------------------------------------------- */
    /*                              Storage variables                             */
    /* -------------------------------------------------------------------------- */

    /// @notice Mapping of the number of shares held by each account.
    mapping(address account => uint256) internal _shares;

    /// @notice The sum of all the shares.
    uint256 internal _totalShares;

    /// @notice The divisor used for conversion between shares and tokens.
    uint256 internal _divisor = MAX_DIVISOR;

    /// @notice Address of a contract to be called upon a rebase event.
    IRebaseCallback internal _rebaseHandler;

    /**
     * @param minter Address to be granted the `minter` role (pass zero address to skip).
     * @param rebaser Address to be granted the `rebaser` role (pass zero address to skip).
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
     * @notice Returns the total supply of tokens in existence.
     * @dev This value is derived from the total number of shares and the current divisor. It does not represent the
     * exact sum of all token balances due to the divisor mechanism.
     * For an accurate representation, consider using the total number of shares via {totalShares}.
     * @return totalSupply_ The total supply of tokens as computed from shares.
     */
    function totalSupply() public view override(ERC20, IERC20) returns (uint256 totalSupply_) {
        return _convertToTokens(_totalShares, Rounding.Closest, _divisor);
    }

    /**
     * @notice Returns the token balance of a given account.
     * @dev The returned value is based on the current divisor and may not represent an accurate balance in terms of
     * shares.
     * For precise calculations, use the number of shares via {sharesOf}.
     * @param account The address of the account to query.
     * @return balance_ The token balance of the account as computed from shares.
     */
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256 balance_) {
        return _convertToTokens(sharesOf(account), Rounding.Closest, _divisor);
    }

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 base functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function burn(uint256 value) public override(ERC20Burnable, IUsdn) {
        super.burn(value);
    }

    /// @inheritdoc IUsdn
    function burnFrom(address account, uint256 value) public override(ERC20Burnable, IUsdn) {
        super.burnFrom(account, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Special token functions                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function sharesOf(address account) public view returns (uint256 shares_) {
        return _shares[account];
    }

    /// @inheritdoc IUsdn
    function totalShares() external view returns (uint256 shares_) {
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
    function divisor() external view returns (uint256 divisor_) {
        return _divisor;
    }

    /// @inheritdoc IUsdn
    function rebaseHandler() external view returns (IRebaseCallback rebaseHandler_) {
        return _rebaseHandler;
    }

    /// @inheritdoc IUsdn
    function maxTokens() public view returns (uint256 maxTokens_) {
        return type(uint256).max / _divisor;
    }

    /// @inheritdoc IUsdn
    function transferShares(address to, uint256 value) external returns (bool success_) {
        address owner = _msgSender();
        _transferShares(owner, to, value, _convertToTokens(value, Rounding.Closest, _divisor));
        return true;
    }

    /// @inheritdoc IUsdn
    function transferSharesFrom(address from, address to, uint256 value) external returns (bool success_) {
        address spender = _msgSender();
        uint256 d = _divisor;
        // in case the number of shares is less than 1 wei of token, we round up to make sure we spend at least 1 wei
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
        // in case the number of shares is less than 1 wei of token, we round up to make sure we spend at least 1 wei
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
            newDivisor = oldDivisor_;
        } else if (newDivisor < MIN_DIVISOR) {
            newDivisor = MIN_DIVISOR;
        }
        if (newDivisor == oldDivisor_) {
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
     * @notice Converts an amount of shares into the corresponding amount of tokens, rounding the division according to
     * `rounding`.
     * @dev If rounding to the nearest integer and the result is exactly at the halfway point, we round up.
     * @param amountShares The amount of shares to convert to tokens.
     * @param rounding The rounding direction: down, closest, or up.
     * @param d The current divisor value used for the conversion.
     * @return tokens_ The calculated equivalent amount of tokens.
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
            uint256 tokensDown = amountShares / d;
            uint256 remainder = amountShares % d;
            if (rounding == Rounding.Down || remainder == 0) {
                // if we want to round down, or there is no remainder to the division, we can return the result
                return tokensDown;
            }

            if (tokensDown == type(uint256).max / d) {
                // early return, we can't have a token amount larger than maxTokens() = uint256.max / _divisor
                return tokensDown;
            }

            uint256 tokensUp = tokensDown + 1;
            if (rounding == Rounding.Up) {
                // we know there is a remainder to the division, so this value is the result of rounding up the quotient
                return tokensUp;
            }

            // determine whether to round up or down when rounding to the nearest value
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
     * @notice Transfers a given amount of shares.
     * @dev Reverts if the `from` or `to` address is the zero address.
     * @param from The address from which shares are transferred.
     * @param to The address to which shares are transferred.
     * @param value The amount of shares to transfer.
     * @param tokenValue The converted token value, used for the {IERC20.Transfer} event.
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
     * @notice Burns a given amount of shares from an account.
     * @dev Reverts if the `account` address is the zero address.
     * @param account The account from which shares are burned.
     * @param value The amount of shares to burn.
     * @param tokenValue The converted token value, used for the {IERC20.Transfer} event.
     */
    function _burnShares(address account, uint256 value, uint256 tokenValue) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _updateShares(account, address(0), value, tokenValue);
    }

    /**
     * @notice Updates the shares of accounts during transferShares, mintShares, or burnShares.
     * @dev Emits a {IERC20.Transfer} event with the token equivalent of the operation.
     * If `from` is the zero address, the operation is a mint.
     * If `to` is the zero address, the operation is a burn.
     * @param from The source address.
     * @param to The destination address.
     * @param value The number of shares to transfer, mint, or burn.
     * @param tokenValue The converted token value, used for the {IERC20.Transfer} event.
     */
    function _updateShares(address from, address to, uint256 value, uint256 tokenValue) internal {
        if (from == address(0)) {
            // overflow check required: the rest of the code assumes that `totalShares` never overflows
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
     * @notice Updates the shares of accounts during transfers, mints, or burns.
     * @dev Emits a {IERC20.Transfer} event.
     * If `from` is the zero address, the operation is a mint.
     * If `to` is the zero address, the operation is a burn.
     * @param from The source address.
     * @param to The destination address.
     * @param value The number of tokens to transfer, mint, or burn.
     */
    function _update(address from, address to, uint256 value) internal override {
        // convert the value to shares, reverts with `UsdnMaxTokensExceeded` if value is too high
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
            // burn: since valueShares <= fromShares <= totalShares, we can safely subtract `valueShares` from
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
