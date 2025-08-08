// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IWusdn } from "../interfaces/Usdn/IWusdn.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ERC-4626 Wrapper for USDN/WUSDN
contract Wusdn4626 is ERC20, IERC4626 {
    using Math for uint256;

    /// @notice The address of the wrapped USDN token.
    IWusdn private constant WUSDN = IWusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);

    /**
     * @notice The address of the USDN token.
     * @dev Retrieve with {asset}.
     */
    IUsdn private immutable USDN;

    /// @notice The ratio of USDN to WUSDN shares.
    uint256 private immutable SHARES_RATIO;

    /// @notice A sanity check in the {mint} function failed.
    error Wusdn4626MintFailed();

    constructor() ERC20("Vault USDN", "vUSDN") {
        USDN = WUSDN.USDN();
        SHARES_RATIO = WUSDN.SHARES_RATIO();
        USDN.approve(address(WUSDN), type(uint256).max);
    }

    /// @inheritdoc IERC4626
    function asset() external view returns (address assetTokenAddress_) {
        return address(USDN);
    }

    /// @inheritdoc IERC4626
    function totalAssets() external view returns (uint256 assets_) {
        // 1 vUSDN = 1 WUSDN token,
        // so we can use the total supply of the wrapper instead of its balance of WUSDN to spare a call
        return WUSDN.previewUnwrap(totalSupply());
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) external view returns (uint256 shares_) {
        return WUSDN.previewWrap(assets);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) public view returns (uint256 assets_) {
        uint256 usdnShares = shares * SHARES_RATIO;
        return usdnShares / USDN.divisor();
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address) external view returns (uint256 maxAssets_) {
        return USDN.maxTokens();
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) external view returns (uint256 shares_) {
        return WUSDN.previewWrap(assets);
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) external returns (uint256 shares_) {
        address caller = _msgSender();
        USDN.transferFrom(caller, address(this), assets);
        // since the transfer above can sometimes retrieve dust which can't be wrapped (less than 1 wei of tokens),
        // we wrap the totality of the balance here so that USDN dust gets removed from the contract (gifted to the
        // depositor) once it reaches more than 1 wei of WUSDN
        shares_ = WUSDN.wrapShares(USDN.sharesOf(address(this)), address(this));
        _mint(receiver, shares_);
        emit Deposit(caller, receiver, assets, shares_);
    }

    /// @inheritdoc IERC4626
    function maxMint(address) external view returns (uint256 maxShares_) {
        return type(uint256).max / SHARES_RATIO;
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) external view returns (uint256 assets_) {
        uint256 usdnShares = shares * SHARES_RATIO;
        return USDN.convertToTokensRoundUp(usdnShares);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) external returns (uint256 assets_) {
        address caller = _msgSender();
        uint256 usdnShares = shares * SHARES_RATIO;
        USDN.transferSharesFrom(caller, address(this), usdnShares);
        uint256 wrappedAmount = WUSDN.wrapShares(usdnShares, address(this));
        // sanity check, should never fail
        if (wrappedAmount != shares) {
            revert Wusdn4626MintFailed();
        }
        _mint(receiver, wrappedAmount);
        assets_ = USDN.convertToTokens(usdnShares);
        emit Deposit(caller, receiver, assets_, wrappedAmount);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address) external view returns (uint256 maxAssets_) {
        return USDN.maxTokens();
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) external view returns (uint256 shares_) {
        uint256 usdnShares = USDN.convertToShares(assets);
        return usdnShares.ceilDiv(SHARES_RATIO);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares_) {
        // Worst-case example:
        // divisor = 1e9
        // assets = 1'000'000'001 USDN (1.000000001B)
        // usdnShares = (1e9 + 1) * divisor = 1.000000001e18
        // wusdn = ceil(1.000000001e18 / SHARES_RATIO) = 2
        // unwrap 2 wei WUSDN to USDN -> 2e18 shares of USDN -> 2B USDN
        // there is 999M+ extra USDN that we send back to the owner
        address caller = _msgSender();
        uint256 usdnShares = USDN.convertToShares(assets);
        shares_ = usdnShares.ceilDiv(SHARES_RATIO); // round up to make sure we always unwrap enough
        if (caller != owner) {
            _spendAllowance(owner, caller, shares_);
        }
        _burn(owner, shares_);
        WUSDN.unwrap(shares_, address(this));
        uint256 receivedShares = USDN.sharesOf(address(this));
        // we might have received more than `assets`
        // the extra shares that were received are sent back to the owner
        // any pre-existing USDN dust gets gifted to the owner too
        if (receivedShares > usdnShares) {
            uint256 diff;
            unchecked {
                diff = receivedShares - usdnShares; // safe because checked above
            }
            USDN.transferShares(owner, diff);
        }
        USDN.transferShares(receiver, usdnShares);
        emit Withdraw(caller, receiver, owner, assets, shares_);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address) external view returns (uint256 maxShares_) {
        return type(uint256).max / SHARES_RATIO;
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
        uint256 balanceBefore = USDN.balanceOf(receiver);
        WUSDN.unwrap(shares, receiver);
        assets_ = USDN.balanceOf(receiver) - balanceBefore;
        emit Withdraw(caller, receiver, owner, assets_, shares);
    }
}
