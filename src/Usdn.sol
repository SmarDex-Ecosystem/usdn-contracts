// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { IUsdn, IUsdnEvents, IUsdnErrors, IERC20, IERC20Permit } from "src/interfaces/IUsdn.sol";

/**
 * @title USDN token contract
 * @notice The USDN token supports the USDN Protocol and is minted when assets are deposited into the vault. When assets
 * are withdrawn from the vault, tokens are burned. The total supply and balances are increased periodically by
 * adjusting a global divisor, so that the price of the token doesn't grow too far past 1 USD.
 * @dev Base implementation of the ERC-20 interface by OpenZeppelin, adapted to support growable balances.
 *
 * Unlike a normal ERC-20, we record balances as a number of shares. The balance is then computed by dividing the
 * shares by a divisor. This allows us to grow the total supply without having to update all balances.
 *
 * Balances and total supply can only grow over time and never shrink.
 */
contract Usdn is ERC20, ERC20Burnable, AccessControl, ERC20Permit, IUsdn {
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

    /// @dev The maximum divisor that can be set. This is the initial value.
    uint256 internal constant MAX_DIVISOR = 1e18;
    /// @dev The minimum divisor that can be set. This corresponds to a growth of 1B times.
    uint256 internal constant MIN_DIVISOR = 1e9;

    /// @dev Divisor used to convert between shares and tokens.
    uint256 internal divisor = MAX_DIVISOR;

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
     * @dev This function must be overridden to fix a solidity compiler error.
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
        uint256 _tokensDown = _amountShares / divisor;
        if (_tokensDown >= maxTokens()) {
            return _tokensDown;
        }
        uint256 _tokensUp = _tokensDown + 1;
        uint256 _sharesDown = _tokensDown * divisor;
        uint256 _sharesUp = _tokensUp * divisor;
        if (_amountShares - _sharesDown < _sharesUp - _amountShares) {
            tokens_ = _tokensDown;
        } else {
            tokens_ = _tokensUp;
        }
    }

    /// @inheritdoc IUsdn
    function convertToShares(uint256 _amountTokens) public view returns (uint256 shares_) {
        if (_amountTokens > maxTokens()) {
            revert UsdnMaxTokensExceeded(_amountTokens);
        }
        shares_ = _amountTokens * divisor;
    }

    /// @inheritdoc IUsdn
    function maxTokens() public view returns (uint256) {
        return type(uint256).max / divisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    /// @inheritdoc IUsdn
    function adjustDivisor(uint256 _divisor) external onlyRole(ADJUSTMENT_ROLE) {
        if (_divisor >= divisor) {
            // Divisor can only be decreased
            revert UsdnInvalidDivisor(_divisor);
        }
        if (_divisor < MIN_DIVISOR) {
            revert UsdnInvalidDivisor(_divisor);
        }
        emit DivisorAdjusted(divisor, _divisor);
        divisor = _divisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Transfer a `value` amount of tokens from `from` to `to`, or alternatively mint (or burn) if `from` or `to`
     * is the zero address.
     * Emits a {Transfer} event.
     * @param _from the source address
     * @param _to the destination address
     * @param _value the amount of tokens to transfer, is internally converted to shares
     */
    function _update(address _from, address _to, uint256 _value) internal override {
        // Convert the value to shares, reverts with `UsdnMaxTokensExceeded()` if _value is too high.
        uint256 _sharesValue = convertToShares(_value);
        uint256 _fromBalance = balanceOf(_from);

        if (_from == address(0)) {
            // Mint: Overflow check required, the rest of the code assumes that totalShares never overflows
            totalShares += _sharesValue;
        } else {
            uint256 _fromShares = shares[_from];
            // Perform the balance check on the amount of tokens, since due to rounding errors, _sharesValue can be
            // slightly larger than _fromShares.
            if (_fromBalance < _value) {
                revert ERC20InsufficientBalance(_from, _fromBalance, _value);
            }
            if (_sharesValue <= _fromShares) {
                unchecked {
                    shares[_from] = _fromShares - _sharesValue;
                }
            } else {
                // Due to a rounding error, _sharesValue can be slightly larger than _fromShares. In this case, we
                // simply set the balance to zero and adjust the transferred amount of shares.
                shares[_from] = 0;
                _sharesValue = _fromShares;
            }
        }

        if (_to == address(0)) {
            // Burn
            totalShares -= _sharesValue;
        } else {
            shares[_to] += _sharesValue;
        }

        emit Transfer(_from, _to, _value);
    }
}
