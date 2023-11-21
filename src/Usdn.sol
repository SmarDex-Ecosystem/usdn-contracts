// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IUsdn, IUsdnEvents, IUsdnErrors, IERC20, IERC20Metadata, IERC20Permit } from "src/interfaces/IUsdn.sol";

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
contract Usdn is IUsdn, IERC20Errors, AccessControl, EIP712, Nonces {
    using Math for uint256;

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

    /// @inheritdoc IERC20Metadata
    uint8 public constant decimals = 18;

    /// @inheritdoc IUsdn
    uint256 public totalShares;

    // Multiplier used to convert between shares and tokens. This is a fixed-point number with 18 decimals.
    uint256 private multiplier = 1e18;

    /**
     * @inheritdoc IUsdn
     * @dev This allows to prevent precision losses when converting from tokens to shares and back.
     * This means that the maximum number of tokens that can exist is `type(uint256).max / 10 ** decimalsOffset`.
     * In practice, due to the rounding in the conversion functions, this number is 1 wei lower.
     */
    uint8 public constant decimalsOffset = 4;

    // Divisor used to convert between shares and tokens. Due to the decimals offset, shares have more precision than
    // tokens.
    uint256 private constant MULTIPLIER_DIVISOR = 10 ** (decimals + decimalsOffset);

    string private constant NAME = "Ultimate Synthetic Delta Neutral";
    string private constant SYMBOL = "USDN";

    constructor(address _minter, address _adjuster) EIP712(NAME, "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

    /// @inheritdoc IERC20Metadata
    function name() external pure returns (string memory) {
        return NAME;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256) {
        return convertToTokens(totalShares);
    }

    /// @inheritdoc IERC20
    function balanceOf(address _account) public view returns (uint256) {
        return convertToTokens(sharesOf(_account));
    }

    /// @inheritdoc IERC20
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowances[_owner][_spender];
    }

    /* -------------------------------------------------------------------------- */
    /*                            Permit view functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view override(IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc IERC20Permit
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
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

    /// @inheritdoc IERC20
    function approve(address _spender, uint256 _value) external returns (bool) {
        _approve(msg.sender, _spender, _value);
        return true;
    }

    /// @inheritdoc IERC20
    function transfer(address _to, uint256 _value) external returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        _spendAllowance(_from, msg.sender, _value);
        _transfer(_from, _to, _value);
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Permit                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IERC20Permit
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
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
        _burn(msg.sender, _value);
    }

    /// @inheritdoc IUsdn
    function burnFrom(address _account, uint256 _value) external {
        _spendAllowance(_account, msg.sender, _value);
        _burn(_account, _value);
    }

    /// @inheritdoc IUsdn
    function convertToShares(uint256 _amountTokens) public view returns (uint256 shares_) {
        uint256 _sharesDown = _amountTokens.mulDiv(MULTIPLIER_DIVISOR, multiplier, Math.Rounding.Floor);
        uint256 _sharesUp = _sharesDown + 1;
        uint256 _tokensDown = _sharesDown.mulDiv(multiplier, MULTIPLIER_DIVISOR, Math.Rounding.Floor);
        uint256 _tokensUp = _sharesUp.mulDiv(multiplier, MULTIPLIER_DIVISOR, Math.Rounding.Floor);
        if (_tokensDown == _amountTokens) {
            shares_ = _sharesDown;
        } else if (_tokensUp == _amountTokens) {
            shares_ = _sharesUp;
        } else {
            shares_ = _amountTokens - _tokensDown <= _tokensUp - _amountTokens ? _sharesDown : _sharesUp;
        }
    }

    /// @inheritdoc IUsdn
    function convertToTokens(uint256 _amountShares) public view returns (uint256 tokens_) {
        uint256 _tokensDown = _amountShares.mulDiv(multiplier, MULTIPLIER_DIVISOR, Math.Rounding.Floor);
        uint256 _tokensUp = _tokensDown + 1;
        uint256 _sharesDown = convertToShares(_tokensDown);
        uint256 _sharesUp = convertToShares(_tokensUp);
        if (_sharesDown == _amountShares) {
            tokens_ = _tokensDown;
        } else if (_sharesUp == _amountShares) {
            tokens_ = _tokensUp;
        } else {
            tokens_ = _amountShares - _sharesDown <= _sharesUp - _amountShares ? _tokensDown : _tokensUp;
        }
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
     * is the zero address.
     * Emits a {Transfer} event.
     * @param _from the source address
     * @param _to the destination address
     * @param _value the amount of tokens to transfer, is internally converted to shares
     */
    function _update(address _from, address _to, uint256 _value) internal {
        uint256 _fromBalance = balanceOf(_from);
        uint256 _sharesValue = convertToShares(_value);
        if (_from == address(0)) {
            // mint
            totalShares += _sharesValue;
        } else {
            uint256 _fromShares = shares[_from];
            if (_fromShares < _sharesValue) {
                revert ERC20InsufficientBalance(_from, _fromBalance, _value);
            }
            shares[_from] = _fromShares - _sharesValue;
        }

        if (_to == address(0)) {
            // burn
            totalShares -= _sharesValue;
        } else {
            shares[_to] += _sharesValue;
        }

        emit Transfer(_from, _to, _value);
    }
}
