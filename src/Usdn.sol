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

import { IUsdn, IUsdnEvents, IUsdnErrors } from "src/interfaces/IUsdn.sol";

/**
 * @title USDN token contract
 * @author @beeb
 * @notice The USDN token supports the USDN Protocol and is minted when assets are deposited into the vault. When assets
 * are withdrawn from the vault, tokens are burned. The total supply and balances are increased periodically by
 * adjusting a multiplier, so that the price of the token doesn't grow too far past 1 USD.
 * @dev Base implementation of the ERC-20 interface by OpenZeppelin, adapted to support growable balances.
 *
 * Unlike a normal ERC-20, we record balances as a number of shares. The balance is then computed by multiplying the
 * shares by a factor >= 1. This allows us to grow the total supply without having to update all balances.
 *
 * Balances and total supply can only grow over time and never shrink.
 */
contract Usdn is
    IUsdn,
    IUsdnEvents,
    IUsdnErrors,
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

    /// @inheritdoc IUsdn
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @inheritdoc IUsdn
    bytes32 public constant ADJUSTMENT_ROLE = keccak256("ADJUSTMENT_ROLE");

    // EIP-712 typehash for the permit method.
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Mapping from account to number of shares
    mapping(address account => uint256) private shares;

    // Mapping of allowances by owner and spender. This is in token units, not shares.
    mapping(address account => mapping(address spender => uint256)) private allowances;

    /// @inheritdoc IUsdn
    uint8 public constant override(IUsdn, IERC20Metadata) decimals = 18;

    /// @inheritdoc IUsdn
    uint256 public totalShares;

    // Multiplier used to convert between shares and tokens. This is a fixed-point number with 18 decimals.
    uint256 private multiplier = 1e18;
    uint256 private constant MULTIPLIER_DIVISOR = 1e18;

    string private constant NAME = "Ultimate Synthetic Delta Neutral";
    string private constant SYMBOL = "USDN";

    constructor(address _minter, address _adjuster) EIP712(NAME, "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        if (_minter != address(0)) {
            _grantRole(MINTER_ROLE, _minter);
        }
        if (_adjuster != address(0)) {
            _grantRole(ADJUSTMENT_ROLE, _adjuster);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 view functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function name() external pure override(IUsdn, IERC20Metadata) returns (string memory) {
        return NAME;
    }

    /// @inheritdoc IUsdn
    function symbol() external pure override(IUsdn, IERC20Metadata) returns (string memory) {
        return SYMBOL;
    }

    /// @inheritdoc IUsdn
    function totalSupply() external view override(IUsdn, IERC20) returns (uint256) {
        return totalShares * multiplier / MULTIPLIER_DIVISOR;
    }

    /// @inheritdoc IUsdn
    function balanceOf(address _account) public view override(IUsdn, IERC20) returns (uint256) {
        return sharesOf(_account) * multiplier / MULTIPLIER_DIVISOR;
    }

    /// @inheritdoc IUsdn
    function allowance(address _owner, address _spender) public view override(IUsdn, IERC20) returns (uint256) {
        return allowances[_owner][_spender];
    }

    /* -------------------------------------------------------------------------- */
    /*                            Permit view functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function nonces(address owner) public view override(IUsdn, IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc IUsdn
    function DOMAIN_SEPARATOR() external view override(IUsdn, IERC20Permit) returns (bytes32) {
        return _domainSeparatorV4();
    }

    /* -------------------------------------------------------------------------- */
    /*                        Special token view functions                        */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function sharesOf(address _account) public view returns (uint256) {
        return shares[_account];
    }

    /* -------------------------------------------------------------------------- */
    /*                              ERC-20 functions                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function approve(address _spender, uint256 _value) external override(IUsdn, IERC20) returns (bool) {
        _approve(_msgSender(), _spender, _value);
        return true;
    }

    /// @inheritdoc IUsdn
    function transfer(address _to, uint256 _value) external override(IUsdn, IERC20) returns (bool) {
        _transfer(_msgSender(), _to, _value);
        return true;
    }

    /// @inheritdoc IUsdn
    function transferFrom(address _from, address _to, uint256 _value) external override(IUsdn, IERC20) returns (bool) {
        address _spender = _msgSender();
        _spendAllowance(_from, _spender, _value);
        _transfer(_from, _to, _value);
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Permit                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override(IUsdn, IERC20Permit) {
        if (block.timestamp > _deadline) {
            revert ERC2612ExpiredSignature(_deadline);
        }

        bytes32 _structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, _useNonce(_owner), _deadline));

        bytes32 _hash = _hashTypedDataV4(_structHash);

        address _signer = ECDSA.recover(_hash, _v, _r, _s);
        if (_signer != _owner) {
            revert ERC2612InvalidSigner(_signer, _owner);
        }

        _approve(_owner, _spender, _value);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Special token functions                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function burn(uint256 _value) external {
        _burn(_msgSender(), _value);
    }

    /// @inheritdoc IUsdn
    function burnFrom(address _account, uint256 _value) external {
        _spendAllowance(_account, _msgSender(), _value);
        _burn(_account, _value);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    /// @inheritdoc IUsdn
    function adjustMultiplier(uint256 _multiplier) external onlyRole(ADJUSTMENT_ROLE) {
        if (_multiplier <= multiplier) {
            // Multiplier can only be increased
            revert UsdnInvalidMultiplier(_multiplier);
        }
        emit MultiplierAdjusted(multiplier, _multiplier);
        multiplier = _multiplier;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Set `value` as the allowance of `spender` over the `owner`'s tokens.
     * Emits an {Approval} event.
     * @param _owner the account that owns the tokens
     * @param _spender the account that will spend the tokens
     * @param _value the amount of tokens to allow
     */
    function _approve(address _owner, address _spender, uint256 _value) internal {
        _approve(_owner, _spender, _value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the emission of the {Approval} event.
     * Used without event emission in {_spendAllowance} and {_transferFrom}.
     * Emits an {Approval} event if `emitEvent` is true.
     * @param _owner the account that owns the tokens
     * @param _spender the account that will spend the tokens
     * @param _value the amount of tokens to allow
     * @param _emitEvent whether to emit the {Approval} event
     */
    function _approve(address _owner, address _spender, uint256 _value, bool _emitEvent) internal {
        if (_owner == address(0)) {
            // this should never happen, because all calling sites check for this
            revert ERC20InvalidApprover(address(0));
        }
        if (_spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        allowances[_owner][_spender] = _value;
        if (_emitEvent) {
            emit Approval(_owner, _spender, _value);
        }
    }

    /**
     * @dev Update allowance of `owner` to `spender`, based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     * @param _owner the account that owns the tokens
     * @param _spender the account that spent the tokens
     * @param _value the amount of tokens spent
     */
    function _spendAllowance(address _owner, address _spender, uint256 _value) internal {
        uint256 _currentAllowance = allowance(_owner, _spender);
        if (_currentAllowance != type(uint256).max) {
            if (_currentAllowance < _value) {
                revert ERC20InsufficientAllowance(_spender, _currentAllowance, _value);
            }
            unchecked {
                _approve(_owner, _spender, _currentAllowance - _value, false);
            }
        }
    }

    /**
     * @dev Create a `value` amount of tokens and assign them to `account`, by transferring it from the zero address.
     * Emits a {Transfer} event with the zero address as `from`.
     * @param _account the account to receive the tokens
     * @param _value the amount of tokens to mint, is internally converted to shares
     */
    function _mint(address _account, uint256 _value) internal {
        if (_account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), _account, _value);
    }

    /**
     * @dev Destroy a `value` amount of tokens from `account`, by transferring it to the zero address, lowering the
     * total supply.
     * Emits a {Transfer} event with the zero address as `to`.
     * @param _account the account to burn the tokens from
     * @param _value the amount of tokens to burn, is internally converted to shares
     */
    function _burn(address _account, uint256 _value) internal {
        if (_account == address(0)) {
            // this should never happen, because all calling sites check for this
            revert ERC20InvalidSender(address(0));
        }
        _update(_account, address(0), _value);
    }

    /**
     * @dev Move a `value` amount of tokens from `from` to `to`.
     * Emits a {Transfer} event.
     * @param _from the source address
     * @param _to the destination address
     * @param _value the amount of tokens to send, is internally converted to shares
     */
    function _transfer(address _from, address _to, uint256 _value) internal {
        if (_from == address(0)) {
            // this should never happen, because all calling sites check for this
            revert ERC20InvalidSender(address(0));
        }
        if (_to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        _update(_from, _to, _value);
    }

    /**
     * @dev Transfer a `value` amount of tokens from `from` to `to`, or alternatively mint (or burn) if `from` or `to`
     * is the zero address. Overflow checks are required because the total supply of tokens could exceed the maximum
     * total number of shares (uint256).
     * Emits a {Transfer} event.
     * @param _from the source address
     * @param _to the destination address
     * @param _value the amount of tokens to transfer, is internally converted to shares
     */
    function _update(address _from, address _to, uint256 _value) internal {
        uint256 _fromBalance = balanceOf(_from);
        uint256 _sharesValue;
        if (_value == _fromBalance) {
            // Transfer all shares, avoids rounding errors
            _sharesValue = shares[_from];
        } else {
            _sharesValue = _value * MULTIPLIER_DIVISOR / multiplier;
        }
        if (_from == address(0)) {
            totalShares += _sharesValue;
        } else {
            uint256 _fromShares = shares[_from];
            if (_fromShares < _sharesValue) {
                revert ERC20InsufficientBalance(_from, _fromBalance, _value);
            }
            shares[_from] = _fromShares - _sharesValue;
        }

        if (_to == address(0)) {
            totalShares -= _sharesValue;
        } else {
            shares[_to] += _sharesValue;
        }

        emit Transfer(_from, _to, _value);
    }
}
