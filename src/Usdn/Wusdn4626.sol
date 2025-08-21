// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";

/// @title ERC-4626 Wrapper for USDN
contract Wusdn4626 is ERC20, IERC4626 {
    /**
     * @notice The address of the USDN token.
     * @dev Retrieve with {asset}.
     */
    IUsdn internal immutable USDN = IUsdn(0xde17a000BA631c5d7c2Bd9FB692EFeA52D90DEE2);

    constructor() ERC20("Vault USDN", "vUSDN") { }

    /// @inheritdoc ERC20
    function decimals() public pure override(ERC20, IERC20Metadata) returns (uint8 decimals_) {
        decimals_ = 36;
    }

    /// @inheritdoc IERC4626
    function asset() external view returns (address assetTokenAddress_) {
        assetTokenAddress_ = address(USDN);
    }

    /// @inheritdoc IERC4626
    function totalAssets() external view returns (uint256 assets_) {
        assets_ = USDN.convertToTokens(totalSupply());
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) external view returns (uint256 shares_) {
        shares_ = USDN.convertToShares(assets);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Since this function MUST round down, we use the divisor directly instead of calling the asset, which
     * would round to nearest.
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets_) {
        assets_ = shares / USDN.divisor();
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address) external pure returns (uint256 maxAssets_) {
        maxAssets_ = type(uint256).max;
    }

    /**
     * @inheritdoc IERC4626
     * @dev When performing a USDN transfer, the amount of USDN shares transferred might be capped at the user's balance
     * if the corresponding token amount is equal to the user's token balance.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares_) {
        uint256 senderShares = USDN.sharesOf(_msgSender());
        uint256 senderBalance = (senderShares > 0) ? USDN.convertToTokens(senderShares) : 0;
        shares_ = USDN.convertToShares(assets);
        if (senderBalance == assets && senderShares < shares_) {
            shares_ = senderShares;
        }
    }

    /**
     * @inheritdoc IERC4626
     * @dev If the contract has excess USDN shares before calling this call, the extra shares (for which no vUSDN
     * have been minted yet), are gifted to the `receiver`.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares_) {
        address caller = _msgSender();
        // using the supply instead of `USDN.sharesOf` to account for extra tokens
        uint256 usdnSharesBefore = totalSupply();
        USDN.transferFrom(caller, address(this), assets);
        uint256 usdnSharesAfter = USDN.sharesOf(address(this));
        unchecked {
            // the USDN shares balance of this contract is greater than or equal to the total supply at all times
            shares_ = usdnSharesAfter - usdnSharesBefore;
        }
        _mint(receiver, shares_);
        emit Deposit(caller, receiver, assets, shares_);
    }

    /// @inheritdoc IERC4626
    function maxMint(address) external pure returns (uint256 maxShares_) {
        maxShares_ = type(uint256).max;
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) external view returns (uint256 assets_) {
        assets_ = USDN.convertToTokensRoundUp(shares);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) external returns (uint256 assets_) {
        address caller = _msgSender();
        USDN.transferSharesFrom(caller, address(this), shares);
        _mint(receiver, shares);
        assets_ = USDN.convertToTokens(shares);
        emit Deposit(caller, receiver, assets_, shares);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Since this function MUST round down, we use the divisor directly instead of calling the asset, which
     * would round to nearest.
     */
    function maxWithdraw(address owner) external view returns (uint256 maxAssets_) {
        maxAssets_ = balanceOf(owner) / USDN.divisor();
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) external view returns (uint256 shares_) {
        shares_ = USDN.convertToShares(assets);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares_) {
        address caller = _msgSender();
        shares_ = USDN.convertToShares(assets);
        if (caller != owner) {
            _spendAllowance(owner, caller, shares_);
        }
        _burn(owner, shares_);
        USDN.transferShares(receiver, shares_);
        emit Withdraw(caller, receiver, owner, assets, shares_);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) external view returns (uint256 maxShares_) {
        maxShares_ = balanceOf(owner);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) external view returns (uint256 assets_) {
        return convertToAssets(shares);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets_) {
        address caller = _msgSender();
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        USDN.transferShares(receiver, shares);
        assets_ = USDN.convertToTokens(shares);
        emit Withdraw(caller, receiver, owner, assets_, shares);
    }
}
