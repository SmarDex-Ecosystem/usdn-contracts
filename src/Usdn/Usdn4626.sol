// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";

/// @title ERC-4626 Wrapper for USDN
contract Usdn4626 is ERC20, IERC4626 {
    using FixedPointMathLib for uint256;

    /**
     * @notice The address of the USDN token.
     * @dev Retrieve with {asset}.
     */
    IUsdn internal immutable USDN;

    /// @notice The ratio used to convert USDN shares to wstUSDN amounts.
    uint256 internal immutable SHARES_RATIO;

    /// @notice Thrown when a deposit would mint 0 shares due to insufficient deposited amount.
    error Usdn4626ZeroShares();

    /// @param usdn The address of the USDN contract.
    constructor(IUsdn usdn) ERC20("Wrapped Staked USDN", "wstUSDN") {
        USDN = usdn;
        SHARES_RATIO = usdn.MAX_DIVISOR();
    }

    /// @inheritdoc IERC20Metadata
    function decimals() public pure override(ERC20, IERC20Metadata) returns (uint8 decimals_) {
        decimals_ = 18;
    }

    /// @inheritdoc IERC4626
    function asset() external view returns (address assetTokenAddress_) {
        assetTokenAddress_ = address(USDN);
    }

    /// @inheritdoc IERC4626
    function totalAssets() external view returns (uint256 assets_) {
        // SAFETY: total supply is at most uint256.max / SHARES_RATIO so multiplication can't overflow
        assets_ = USDN.convertToTokens(totalSupply().rawMul(SHARES_RATIO));
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view returns (uint256 shares_) {
        shares_ = USDN.convertToShares(assets).rawDiv(SHARES_RATIO); // SAFETY: SHARES_RATIO is never zero
    }

    /**
     * @inheritdoc IERC4626
     * @dev Since this function MUST round down, we use the divisor directly instead of calling the asset, which
     * would round to nearest.
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets_) {
        assets_ = shares.fullMulDiv(SHARES_RATIO, USDN.divisor());
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address) external pure returns (uint256 maxAssets_) {
        maxAssets_ = type(uint256).max;
    }

    /// @inheritdoc IERC4626
    function maxMint(address) external pure returns (uint256 maxShares_) {
        maxShares_ = type(uint256).max;
    }

    /**
     * @inheritdoc IERC4626
     * @dev Since this function MUST round down, we use the divisor directly instead of calling the asset, which
     * would round to nearest.
     */
    function maxWithdraw(address owner) external view returns (uint256 maxAssets_) {
        // SAFETY: balance of a user cannot exceed uint256.max / SHARES_RATIO
        // SAFETY: USDN divisor cannot be zero
        maxAssets_ = balanceOf(owner).rawMul(SHARES_RATIO).rawDiv(USDN.divisor());
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) external view returns (uint256 maxShares_) {
        maxShares_ = balanceOf(owner);
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) external view returns (uint256 shares_) {
        shares_ = _getDepositUsdnShares(assets).rawDiv(SHARES_RATIO); // SAFETY: SHARES_RATIO is never zero
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) external view returns (uint256 assets_) {
        assets_ = USDN.convertToTokensRoundUp(shares * SHARES_RATIO);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) external view returns (uint256 shares_) {
        shares_ = USDN.convertToShares(assets).divUp(SHARES_RATIO);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) external view returns (uint256 assets_) {
        assets_ = convertToAssets(shares);
    }

    /**
     * @inheritdoc IERC4626
     * @dev If the contract has excess USDN shares before calling this function, the extra shares (for which no wrapper
     * shares have been minted yet), are gifted to the `receiver`.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares_) {
        uint256 usdnShares = _getDepositUsdnShares(assets);
        // using the supply instead of `USDN.sharesOf` to account for extra tokens
        // SAFETY: total supply cannot exceed uint256.max / SHARES_RATIO
        uint256 usdnSharesBefore = totalSupply().rawMul(SHARES_RATIO);
        USDN.transferSharesFrom(msg.sender, address(this), usdnShares); // we ensure the balance delta will be `assets`
        uint256 usdnSharesAfter = USDN.sharesOf(address(this));
        // SAFETY: the USDN shares balance of this contract is greater than or equal to the total supply * SHARES_RATIO
        // at all times
        // SAFETY: SHARES_RATIO is never zero
        shares_ = usdnSharesAfter.rawSub(usdnSharesBefore).rawDiv(SHARES_RATIO);
        if (shares_ == 0) {
            revert Usdn4626ZeroShares();
        }
        _mint(receiver, shares_);
        emit Deposit(msg.sender, receiver, assets, shares_);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) external returns (uint256 assets_) {
        _mint(receiver, shares);
        uint256 balanceBefore = USDN.balanceOf(msg.sender);
        USDN.transferSharesFrom(msg.sender, address(this), shares * SHARES_RATIO);
        // check how much the receiver's balance decreases to honor invariant
        assets_ = balanceBefore.rawSub(USDN.balanceOf(msg.sender)); // SAFETY: balance can only decrease during transfer
        emit Deposit(msg.sender, receiver, assets_, shares);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares_) {
        uint256 usdnShares = USDN.convertToShares(assets);
        // round up burned amount to make sure we have enough shares available to be transferred to the receiver
        shares_ = usdnShares.divUp(SHARES_RATIO);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares_);
        }
        _burn(owner, shares_);
        // the excess USDN share dust (shares_ * SHARES_RATIO - usdnShares) remains in the contract to be gifted to the
        // next depositor
        // this is at most 1 gwei of USDN, often less
        USDN.transferShares(receiver, usdnShares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares_);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets_) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        // check how much the receiver's balance increases after receiving USDN to honor invariant
        uint256 balanceBefore = USDN.balanceOf(receiver);
        // SAFETY: a user cannot have more shares than uint256.max / SHARES_RATIO
        USDN.transferShares(receiver, shares.rawMul(SHARES_RATIO));
        assets_ = USDN.balanceOf(receiver).rawSub(balanceBefore); // SAFETY: balance can only increase during transfer
        emit Withdraw(msg.sender, receiver, owner, assets_, shares);
    }

    /**
     * @notice Converts an assets amount into a corresponding number of USDN shares, taking into account the sender's
     * shares balance.
     * @dev When performing a USDN transfer, the amount of USDN shares transferred might be capped at the user's balance
     * if the corresponding token amount is equal to the user's token balance.
     * @param assets The amount of USDN tokens.
     * @return shares_ The number of shares that would be transferred from `msg.sender`.
     */
    function _getDepositUsdnShares(uint256 assets) internal view returns (uint256 shares_) {
        shares_ = USDN.convertToShares(assets);
        // due to rounding in the USDN contract, there may be a small difference between the amount
        // of shares converted from the USDN amount and the shares held by the user.
        if (USDN.balanceOf(msg.sender) == assets) {
            shares_ = shares_.min(USDN.sharesOf(msg.sender));
        }
    }
}
