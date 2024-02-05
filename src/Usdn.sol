// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

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
contract Usdn is IUsdn, ERC20Permit, ERC20Burnable, AccessControl {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @inheritdoc IUsdn
    bytes32 public constant ADJUSTMENT_ROLE = keccak256("ADJUSTMENT_ROLE");

    /// @dev The maximum divisor that can be set. This is the initial value.
    uint256 public constant MAX_DIVISOR = 1e18;

    /**
     * @dev The minimum divisor that can be set. This corresponds to a growth of 1B times. Technically, 1e5 would still
     * work without precision errors.
     */
    uint256 public constant MIN_DIVISOR = 1e9;

    string internal constant NAME = "Ultimate Synthetic Delta Neutral";
    string internal constant SYMBOL = "USDN";

    /* -------------------------------------------------------------------------- */
    /*                              Storage variables                             */
    /* -------------------------------------------------------------------------- */

    /// @dev Mapping from account to number of shares
    mapping(address account => uint256) internal _shares;

    /// @dev Sum of all the shares
    uint256 internal _totalShares;

    /// @dev Divisor used to convert between shares and tokens.
    uint256 internal _divisor = MAX_DIVISOR;

    constructor(address minter, address adjuster) ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (minter != address(0)) {
            _grantRole(MINTER_ROLE, minter);
        }
        if (adjuster != address(0)) {
            _grantRole(ADJUSTMENT_ROLE, adjuster);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 view functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IERC20
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return convertToTokens(_totalShares);
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return convertToTokens(sharesOf(account));
    }

    /**
     * @inheritdoc IERC20Permit
     * @dev This function must be overridden to fix a solidity compiler error.
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
    function convertToTokens(uint256 amountShares) public view returns (uint256 tokens_) {
        uint256 tokensDown = amountShares / _divisor;
        if (tokensDown == maxTokens()) {
            // early return, we can't have a token amount larger than maxTokens()
            return tokensDown;
        }
        uint256 tokensUp = tokensDown + 1;
        // slither-disable-next-line divide-before-multiply
        uint256 sharesDown = tokensDown * _divisor;
        // slither-disable-next-line divide-before-multiply
        uint256 sharesUp = tokensUp * _divisor;
        if (amountShares - sharesDown <= sharesUp - amountShares) {
            tokens_ = tokensDown;
        } else {
            tokens_ = tokensUp;
        }
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
    function maxTokens() public view returns (uint256) {
        return type(uint256).max / _divisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @inheritdoc IUsdn
    function adjustDivisor(uint256 newDivisor) external onlyRole(ADJUSTMENT_ROLE) {
        if (newDivisor >= _divisor) {
            // Divisor can only be decreased
            revert UsdnInvalidDivisor(newDivisor);
        }
        if (newDivisor < MIN_DIVISOR) {
            revert UsdnInvalidDivisor(newDivisor);
        }
        emit DivisorAdjusted(_divisor, newDivisor);
        _divisor = newDivisor;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Transfer a `value` amount of tokens from `from` to `to`, or alternatively mint (or burn) if `from` or `to`
     * is the zero address.
     * Emits a {Transfer} event.
     * @param from the source address
     * @param to the destination address
     * @param value the amount of tokens to transfer, is internally converted to shares
     */
    function _update(address from, address to, uint256 value) internal override {
        // Convert the value to shares, reverts with `UsdnMaxTokensExceeded()` if value is too high.
        uint256 valueShares = convertToShares(value);
        uint256 fromBalance = balanceOf(from);

        if (from == address(0)) {
            // Mint
            unchecked {
                uint256 res = _totalShares + valueShares;
                // Overflow check required, the rest of the code assumes that totalShares never overflows
                if (res < _totalShares) {
                    revert UsdnTotalSupplyOverflow();
                }
                _totalShares = res;
            }
        } else {
            uint256 fromShares = _shares[from];
            // Perform the balance check on the amount of tokens, since due to rounding errors, valueShares can be
            // slightly larger than fromShares.
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            if (valueShares <= fromShares) {
                // Since valueShares <= fromShares, we can safely subtract valueShares from fromShares
                unchecked {
                    _shares[from] -= valueShares;
                }
            } else {
                // Due to a rounding error, valueShares can be slightly larger than fromShares. In this case, we
                // simply set the balance to zero and adjust the transferred amount of shares.
                _shares[from] = 0;
                valueShares = fromShares;
            }
        }

        if (to == address(0)) {
            // Burn: Since valueShares <= fromShares <= totalShares, we can safely subtract valueShares from
            // totalShares
            unchecked {
                _totalShares -= valueShares;
            }
        } else {
            // Since shares + valueShares <= totalShares, we can safely add valueShares to the user shares
            unchecked {
                _shares[to] += valueShares;
            }
        }

        emit Transfer(from, to, value);
    }
}
