// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IWusdn } from "../interfaces/Usdn/IWusdn.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @title ERC-4626 Wrapper for USDN
 * @dev This wrapper delegates to WUSDN internally to simplify normalization to 18 decimals.
 */
contract Wusdn4626 is ERC20, IERC4626 {
    using FixedPointMathLib for uint256;

    /// @notice The address of the wrapped USDN token.
    IWusdn internal constant WUSDN = IWusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);

    /**
     * @notice The address of the USDN token.
     * @dev Retrieve with {asset}.
     */
    IUsdn internal immutable USDN;

    /// @notice The ratio of USDN to WUSDN shares.
    uint256 internal immutable SHARES_RATIO;

    constructor() ERC20("Vault USDN", "vUSDN") {
        USDN = WUSDN.USDN();
        SHARES_RATIO = WUSDN.SHARES_RATIO();
        USDN.approve(address(WUSDN), type(uint256).max);
    }

    /// @inheritdoc IERC4626
    function asset() external view returns (address assetTokenAddress_) {
        assetTokenAddress_ = address(USDN);
    }

    /// @inheritdoc IERC4626
    function totalAssets() external view returns (uint256 assets_) {
        // 1 vUSDN = 1 WUSDN token,
        // so we can use the total supply of the wrapper instead of its balance of WUSDN to spare a call
        // this doesn't account for WUSDN tokens which would have been directly sent to this contract
        // we directly call USDN.convertToTokens instead of WUSDN.previewUnwrap for efficiency
        assets_ = USDN.convertToTokens(totalSupply() * SHARES_RATIO);
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view returns (uint256 shares_) {
        // we directly call USDN.convertToShares instead of WUSDN.previewWrap for efficiency
        shares_ = USDN.convertToShares(assets).rawDiv(SHARES_RATIO); // SHARES_RATIO is never zero
    }

    /**
     * @inheritdoc IERC4626
     * @dev Since this function MUST round down, we use the divisor directly instead of calling the asset, which
     * would round to nearest.
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets_) {
        uint256 usdnShares = shares * SHARES_RATIO;
        assets_ = usdnShares.rawDiv(USDN.divisor()); // divisor is never zero
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address) external pure returns (uint256 maxAssets_) {
        maxAssets_ = type(uint256).max;
    }

    /// @inheritdoc IERC4626
    function maxMint(address) external pure returns (uint256 maxShares_) {
        maxShares_ = type(uint256).max;
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) external view returns (uint256 maxAssets_) {
        uint256 usdnShares = USDN.convertToShares(balanceOf(owner));
        maxAssets_ = usdnShares.rawDiv(SHARES_RATIO); // SHARES_RATIO is never zero
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) external view returns (uint256 maxShares_) {
        maxShares_ = balanceOf(owner);
    }

    /**
     * @inheritdoc IERC4626
     * @dev When performing a USDN transfer, the amount of USDN shares transferred might be capped at the user's balance
     * if the corresponding token amount is equal to the user's token balance.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares_) {
        uint256 senderShares = USDN.sharesOf(msg.sender);
        uint256 senderBalance = (senderShares > 0) ? USDN.convertToTokens(senderShares) : 0;
        uint256 usdnShares = USDN.convertToShares(assets);
        if (senderBalance == assets && senderShares < usdnShares) {
            usdnShares = senderShares;
        }
        shares_ = usdnShares.rawDiv(SHARES_RATIO); // SHARES_RATIO is never zero
    }

    /**
     * @inheritdoc IERC4626
     * @dev Since this function MUST round up, we use the conversion function `convertToTokensRoundUp`.
     */
    function previewMint(uint256 shares) external view returns (uint256 assets_) {
        uint256 usdnShares = shares * SHARES_RATIO;
        assets_ = USDN.convertToTokensRoundUp(usdnShares);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Since this function MUST round up, we use ceiling division.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares_) {
        uint256 usdnShares = USDN.convertToShares(assets);
        shares_ = usdnShares.divUp(SHARES_RATIO);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) external view returns (uint256 assets_) {
        assets_ = convertToAssets(shares);
    }

    /**
     * @inheritdoc IERC4626
     * @notice Any extra USDN or WUSDN which would have been sent to the contract by mistake (without interacting with
     * this contract's external functions) is gifted to the receiver.
     * This is to avoid that funds remain stuck in the contract forever.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares_) {
        // gifting any extra WUSDN sent to the contract directly to the depositor
        // the WUSDN balance of this contract is greater than or equal to the total supply at all times
        shares_ = WUSDN.balanceOf(address(this)).rawSub(totalSupply());
        USDN.transferFrom(msg.sender, address(this), assets);
        // since the transfer above can sometimes retrieve dust which can't be wrapped (less than 1 wei of tokens),
        // we wrap the totality of the USDN balance here so that USDN dust gets removed from the contract (gifted to the
        // depositor) once it reaches more than 1 wei of WUSDN
        // total supply of WUSDN cannot exceed (uint256.max / SHARES_RATIO) so overflow check is not needed
        shares_ = shares_.rawAdd(WUSDN.wrapShares(USDN.sharesOf(address(this)), address(this)));
        _mint(receiver, shares_);
        emit Deposit(msg.sender, receiver, assets, shares_);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) external returns (uint256 assets_) {
        uint256 usdnShares = shares * SHARES_RATIO;
        uint256 balanceBefore = USDN.balanceOf(msg.sender);
        USDN.transferSharesFrom(msg.sender, address(this), usdnShares);
        // check how much the receiver's balance decreases to honor invariant
        assets_ = balanceBefore.rawSub(USDN.balanceOf(msg.sender)); // balance can only decrease during transfer
        uint256 wrappedAmount = WUSDN.wrapShares(usdnShares, address(this));
        require(wrappedAmount == shares); // sanity check, should never fail
        _mint(receiver, wrappedAmount);
        emit Deposit(msg.sender, receiver, assets_, wrappedAmount);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares_) {
        // we need to account for extra unwrapped USDN due to 18 decimals precision of WUSDN and rebase
        // worst-case example:
        // divisor = 1e9
        // assets = 1'000'000'001 USDN (1.000000001B)
        // usdnShares = (1e9 + 1) * divisor = 1.000000001e18
        // wusdn = ceil(1.000000001e18 / SHARES_RATIO) = 2
        // unwrap 2 wei WUSDN to USDN -> 2e18 shares of USDN -> 2B USDN
        // there is 999M+ extra USDN that we send back to the owner
        uint256 usdnShares = USDN.convertToShares(assets); // should go to receiver
        shares_ = usdnShares.divUp(SHARES_RATIO); // round up to make sure we always unwrap enough
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares_);
        }
        _burn(owner, shares_);
        WUSDN.unwrap(shares_, address(this));
        uint256 receivedShares = USDN.sharesOf(address(this));
        // we might have received more than `assets`
        // the extra shares that were received are sent back to the owner
        // any pre-existing USDN dust gets gifted to the owner too to avoid accumulating it here
        if (receivedShares > usdnShares) {
            uint256 diff = receivedShares.rawSub(usdnShares); // safe because checked above
            USDN.transferShares(owner, diff);
        }
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
        WUSDN.unwrap(shares, receiver);
        assets_ = USDN.balanceOf(receiver).rawSub(balanceBefore); // balance can only increase during unwrap
        emit Withdraw(msg.sender, receiver, owner, assets_, shares);
    }
}
