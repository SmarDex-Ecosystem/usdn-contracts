// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";

import { IUSDN, IUSDNEvents, IUSDNErrors } from "src/interfaces/IUSDN.sol";

/**
 * @dev Base implementation of the ERC-20 interface by OpenZeppelin, adapted to support growable balances.
 *
 * Unlike a normal ERC-20, we record balances as a number of shares. The balance is then computed by multiplying the
 * shares by a factor >= 1. This allows us to grow the total supply without having to update all balances.
 *
 * Balances and total supply can only grow over time and never shrink.
 */
contract USDN is
    IUSDN,
    IUSDNEvents,
    IUSDNErrors,
    Context,
    IERC20,
    IERC20Metadata,
    IERC20Errors,
    AccessControl,
    IERC20Permit,
    EIP712,
    Nonces
{
    /* -------------------------------------------------------------------------- */
    /*                           Variables and constants                          */
    /* -------------------------------------------------------------------------- */

    // Role required to mint new shares.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Role required to adjust the multiplier.
    bytes32 public constant ADJUSTMENT_ROLE = keccak256("ADJUSTMENT_ROLE");

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Mapping from account to number of shares
    mapping(address account => uint256) private _shares;

    // Mapping of allowances by owner and spender. This is in token units, not shares.
    mapping(address account => mapping(address spender => uint256)) private _allowances;

    uint8 public constant override(IUSDN, IERC20Metadata) decimals = 18;

    uint256 private _totalShares;
    // Multiplier used to convert between shares and tokens. This is a fixed-point number with 18 decimals.
    uint256 private _multiplier = 1e18;
    uint256 private constant MULTIPLIER_DIVISOR = 1e18;

    string private constant NAME = "Ultimate Synthetic Delta Neutral";
    string private constant SYMBOL = "USDN";

    constructor(address minter, address adjustment) EIP712(NAME, "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        if (minter != address(0)) {
            _grantRole(MINTER_ROLE, minter);
        }
        if (adjustment != address(0)) {
            _grantRole(ADJUSTMENT_ROLE, adjustment);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 view functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUSDN
    function name() external pure override(IUSDN, IERC20Metadata) returns (string memory) {
        return NAME;
    }

    /// @inheritdoc IUSDN
    function symbol() external pure override(IUSDN, IERC20Metadata) returns (string memory) {
        return SYMBOL;
    }

    /// @inheritdoc IUSDN
    function totalSupply() external view override(IUSDN, IERC20) returns (uint256) {
        return totalShares() * _multiplier / MULTIPLIER_DIVISOR;
    }

    /// @inheritdoc IUSDN
    function balanceOf(address account) public view override(IUSDN, IERC20) returns (uint256) {
        return sharesOf(account) * _multiplier / MULTIPLIER_DIVISOR;
    }

    /// @inheritdoc IUSDN
    function allowance(address owner, address spender) public view override(IUSDN, IERC20) returns (uint256) {
        return _allowances[owner][spender];
    }

    /* -------------------------------------------------------------------------- */
    /*                            Permit view functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUSDN
    function nonces(address owner) public view override(IUSDN, IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc IUSDN
    function DOMAIN_SEPARATOR() external view override(IUSDN, IERC20Permit) returns (bytes32) {
        return _domainSeparatorV4();
    }

    /* -------------------------------------------------------------------------- */
    /*                        Special token view functions                        */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUSDN
    function totalShares() public view returns (uint256) {
        return _totalShares;
    }

    /// @inheritdoc IUSDN
    function sharesOf(address account) public view returns (uint256) {
        return _shares[account];
    }

    /* -------------------------------------------------------------------------- */
    /*                              ERC-20 functions                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUSDN
    function approve(address spender, uint256 value) external override(IUSDN, IERC20) returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /// @inheritdoc IUSDN
    function transfer(address to, uint256 value) external override(IUSDN, IERC20) returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /// @inheritdoc IUSDN
    function transferFrom(address from, address to, uint256 value) external override(IUSDN, IERC20) returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Permit                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUSDN
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override(IUSDN, IERC20Permit)
    {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }

        _approve(owner, spender, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Special token functions                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUSDN
    function burn(uint256 value) external {
        _burn(_msgSender(), value);
    }

    /// @inheritdoc IUSDN
    function burnFrom(address account, uint256 value) external {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUSDN
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @inheritdoc IUSDN
    function adjustMultiplier(uint256 multiplier) external onlyRole(ADJUSTMENT_ROLE) {
        if (multiplier <= _multiplier) {
            // Multiplier can only be increased
            revert InvalidMultiplier(multiplier);
        }
        emit MultiplierAdjusted(_multiplier, multiplier);
        _multiplier = multiplier;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Set `value` as the allowance of `spender` over the `owner`'s tokens.
     * @dev Emits an {Approval} event.
     * @param owner the account that owns the tokens
     * @param spender the account that will spend the tokens
     * @param value the amount of tokens to allow
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the emission of the {Approval} event.
     * Used without event emission in {_spendAllowance} and {_transferFrom}.
     * @dev Emits an {Approval} event if `emitEvent` is true.
     * @param owner the account that owns the tokens
     * @param spender the account that will spend the tokens
     * @param value the amount of tokens to allow
     * @param emitEvent whether to emit the {Approval} event
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Update allowance of `owner` to `spender`, based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     * @param owner the account that owns the tokens
     * @param spender the account that spent the tokens
     * @param value the amount of tokens spent
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    /**
     * @dev Create a `value` amount of tokens and assign them to `account`, by transferring it from the zero address.
     * @dev Emits a {Transfer} event with the zero address as `from`.
     * @param account the account to receive the tokens
     * @param value the amount of tokens to mint, is internally converted to shares
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Destroy a `value` amount of tokens from `account`, by transferring it to the zero address, lowering the
     * total supply.
     * @dev Emits a {Transfer} event with the zero address as `to`.
     * @param account the account to burn the tokens from
     * @param value the amount of tokens to burn, is internally converted to shares
     */
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /**
     * @dev Move a `value` amount of tokens from `from` to `to`.
     * @dev Emits a {Transfer} event.
     * @param from the source address
     * @param to the destination address
     * @param value the amount of tokens to send, is internally converted to shares
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        _update(from, to, value);
    }

    /**
     * @dev Transfer a `value` amount of tokens from `from` to `to`, or alternatively mint (or burn) if `from` or `to`
     * is the zero address. Overflow checks are required because the total supply of tokens could exceed the maximum
     * total number of shares (uint256).
     * @dev Emits a {Transfer} event.
     * @param from the source address
     * @param to the destination address
     * @param value the amount of tokens to transfer, is internally converted to shares
     */
    function _update(address from, address to, uint256 value) internal {
        uint256 fromBalance = balanceOf(from);
        uint256 _sharesValue;
        if (value == fromBalance) {
            // Transfer all shares, avoids rounding errors
            _sharesValue = _shares[from];
        } else {
            _sharesValue = value * MULTIPLIER_DIVISOR / _multiplier;
        }
        if (from == address(0)) {
            _totalShares += _sharesValue;
        } else {
            uint256 fromShares = _shares[from];
            if (fromShares < _sharesValue) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            _shares[from] = fromShares - _sharesValue;
        }

        if (to == address(0)) {
            _totalShares -= _sharesValue;
        } else {
            _shares[to] += _sharesValue;
        }

        emit Transfer(from, to, value);
    }
}
