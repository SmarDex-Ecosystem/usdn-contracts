// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IUsdn, IUsdnEvents, IUsdnErrors, IERC20, IERC20Permit } from "src/interfaces/IUsdn.sol";

/**
 * @title USDN token contract
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
contract Usdn is ERC20, ERC20Burnable, AccessControl, ERC20Permit, IUsdn {
    using Math for uint256;

    /* -------------------------------------------------------------------------- */
    /*                           Variables and constants                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @inheritdoc IUsdn
    bytes32 public constant ADJUSTMENT_ROLE = keccak256("ADJUSTMENT_ROLE");

    /// @dev Mapping from account to number of shares
    mapping(address account => uint256) private shares;

    /// @inheritdoc IUsdn
    uint256 public totalShares;

    /// @dev Multiplier used to convert between shares and tokens. This is a fixed-point number with 9 decimals.
    uint256 internal multiplier = 1e9;

    /// @dev The maximum multiplier that can be set. Corresponds to a 1B ratio between tokens and shares.
    uint256 internal constant MAX_MULTIPLIER = 1e18;

    /**
     * @dev The additional precision for shares compared to tokens.
     * This allows to prevent precision losses when converting from tokens to shares and back.
     *
     * Given offset is 11
     * And multiplier is 1e9 (min):
     * tokens = shares * multiplier / MULTIPLIER_DIVISOR = shares * 1e9 / 10**(9+11) = shares / 1e11
     * shares = tokens * MULTIPLIER_DIVISOR / multiplier = tokens * 10**(9+11) / 1e9 = tokens * 1e11
     *
     * Given multiplier is 1e18 (max):
     * tokens = shares * multiplier / MULTIPLIER_DIVISOR = shares * 1e18 / 10**(9+11) = shares / 1e2
     * shares = tokens * MULTIPLIER_DIVISOR / multiplier = tokens * 10**(9+11) / 1e18 = tokens * 1e2
     *
     * We always have more precision in shares than in tokens, so we don't have rounding issues.
     */
    uint8 internal constant DECIMALS_OFFSET = 11;

    /**
     * @dev Divisor used to convert between shares and tokens.
     * Due to the decimals offset, shares have more precision than tokens even at MAX_MULTIPLIER.
     */
    uint256 internal constant MULTIPLIER_DIVISOR = 10 ** (9 + DECIMALS_OFFSET);

    /**
     * @dev The maximum number of tokens that can exist is limited due to the conversion to shares and the effect of
     * the multiplier.
     *
     * When trying to mint MAX_TOKENS at multiplier 1e9, we get:
     * shares = MAX_TOKENS * 1e11 = type(uint256).max - 113_129_639_935 ~= 1.16e77
     *
     * When trying to mint MAX_TOKENS at multiplier 1e18, we get:
     * shares = MAX_TOKENS * 1e2 ~= 1.16e68
     */
    uint256 internal constant MAX_TOKENS = (type(uint256).max / 10 ** DECIMALS_OFFSET) - 1;

    string private constant NAME = "Ultimate Synthetic Delta Neutral";
    string private constant SYMBOL = "USDN";

    constructor(address _minter, address _adjuster) ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
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

    /// @inheritdoc IERC20
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return convertToTokens(totalShares);
    }

    /// @inheritdoc IERC20
    function balanceOf(address _account) public view override(ERC20, IERC20) returns (uint256) {
        return convertToTokens(sharesOf(_account));
    }

    /**
     * @inheritdoc IERC20Permit
     * @dev This function must be overriden to fix a solidity compiler error.
     */
    function nonces(address owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Special token functions                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function sharesOf(address _account) public view returns (uint256) {
        return shares[_account];
    }

    /// @inheritdoc IUsdn
    function convertToTokens(uint256 _amountShares) public view returns (uint256 tokens_) {
        uint256 _tokensDown = _amountShares.mulDiv(multiplier, MULTIPLIER_DIVISOR, Math.Rounding.Floor);
        uint256 _tokensUp = _tokensDown + 1;
        uint256 _sharesDown = _convertToShares(_tokensDown);
        uint256 _sharesUp = _convertToShares(_tokensUp);
        if (_sharesDown == _amountShares) {
            tokens_ = _tokensDown;
        } else if (_sharesUp == _amountShares) {
            tokens_ = _tokensUp;
        } else {
            tokens_ = _amountShares - _sharesDown <= _sharesUp - _amountShares ? _tokensDown : _tokensUp;
        }
    }

    /// @inheritdoc IUsdn
    function convertToShares(uint256 _amountTokens) public view returns (uint256 shares_) {
        if (_amountTokens > MAX_TOKENS) {
            revert UsdnMaxTokensExceeded(_amountTokens);
        }
        shares_ = _convertToShares(_amountTokens);
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
        if (_multiplier > MAX_MULTIPLIER) {
            revert UsdnInvalidMultiplier(_multiplier);
        }
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
     * @dev Converts a number of tokens to the corresponding amount of shares.
     * This internal function doesn't check the input value, it should be done by the caller if needed.
     * @param _amountTokens the amount of tokens to convert to shares
     * @return shares_ the corresponding amount of shares
     */
    function _convertToShares(uint256 _amountTokens) internal view returns (uint256 shares_) {
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

    /**
     * @dev Transfer a `value` amount of tokens from `from` to `to`, or alternatively mint (or burn) if `from` or `to`
     * is the zero address.
     * Emits a {Transfer} event.
     * @param _from the source address
     * @param _to the destination address
     * @param _value the amount of tokens to transfer, is internally converted to shares
     */
    function _update(address _from, address _to, uint256 _value) internal override {
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
