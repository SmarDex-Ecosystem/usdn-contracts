// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";
import { IUsdnProtocolVault } from "src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

abstract contract UsdnProtocolVault is IUsdnProtocolVault, UsdnProtocolCore {
    using SafeCast for int256;

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice, uint128 timestamp) public view returns (uint256 price_) {
        price_ = _calcUsdnPrice(
            vaultAssetAvailableWithFunding(currentPrice, timestamp).toUint256(),
            currentPrice,
            _usdn.totalSupply(),
            _assetDecimals
        );
    }

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        price_ = usdnPrice(currentPrice, uint128(block.timestamp));
    }

    /**
     * @notice Calculate the price of the USDN token as a function of its total supply, the vault balance and the
     * underlying asset price.
     * @param vaultBalance The vault balance
     * @param assetPrice The price of the asset
     * @param usdnTotalSupply The total supply of the USDN token
     * @param assetDecimals The number of decimals of the underlying asset
     * @return price_ The price of the USDN token
     */
    function _calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        internal
        pure
        returns (uint256 price_)
    {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** TOKENS_DECIMALS, usdnTotalSupply * 10 ** assetDecimals
        );
    }

    /**
     * @notice Calculate the amount of sdex to burn when minting USDN tokens
     * @param usdnAmount The amount of usdn to be minted
     * @param sdexBurnRatio The ratio of SDEX to burn for each minted USDN
     * @return sdexToBurn_ The amount of SDEX to burn for the given USDN amount
     */
    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) internal pure returns (uint256 sdexToBurn_) {
        sdexToBurn_ = FixedPointMathLib.fullMulDiv(usdnAmount, sdexBurnRatio, SDEX_BURN_ON_DEPOSIT_DIVISOR);
    }

    /**
     * @notice Calculate the required USDN total supply to reach `targetPrice`
     * @param vaultBalance The balance of the vault
     * @param assetPrice The price of the underlying asset
     * @param targetPrice The target USDN price to reach
     * @param assetDecimals The number of decimals of the asset
     * @return totalSupply_ The required total supply to achieve `targetPrice`
     */
    function _calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        internal
        pure
        returns (uint256 totalSupply_)
    {
        totalSupply_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** TOKENS_DECIMALS, uint256(targetPrice) * 10 ** assetDecimals
        );
    }

    /**
     * @notice Check if a USDN rebase is required and adjust divisor if needed.
     * @dev Note: only call this function after `_applyPnlAndFunding` has been called to update the balances.
     * @param assetPrice The current price of the underlying asset
     * @return rebased_ Whether a rebase was performed
     */
    function _usdnRebase(uint128 assetPrice) internal returns (bool rebased_) {
        _lastRebaseCheck = block.timestamp;
        IUsdn usdn = _usdn;
        uint256 divisor = usdn.divisor();
        if (divisor <= _usdnMinDivisor) {
            // no need to rebase, the USDN divisor cannot go lower
            return false;
        }
        uint256 balanceVault = _balanceVault;
        uint8 assetDecimals = _assetDecimals;
        uint256 usdnTotalSupply = usdn.totalSupply();
        uint256 uPrice = _calcUsdnPrice(balanceVault, assetPrice, usdnTotalSupply, assetDecimals);
        if (uPrice <= _usdnRebaseThreshold) {
            return false;
        }
        uint256 targetTotalSupply = _calcRebaseTotalSupply(balanceVault, assetPrice, _targetUsdnPrice, assetDecimals);
        uint256 newDivisor = FixedPointMathLib.fullMulDiv(usdnTotalSupply, divisor, targetTotalSupply);
        usdn.rebase(newDivisor);
        rebased_ = true;
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset
     * @param amount The amount of asset to be converted into USDN
     * @param vaultBalance The balance of the vault (not used for initialization)
     * @param usdnTotalSupply The total supply of USDN (not used for initialization)
     * @param price The price of the asset (only used for initialization)
     * @return toMint_ The amount of USDN to mint
     * @dev The amount of USDN to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance.
     */
    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        internal
        view
        returns (uint256 toMint_)
    {
        if (vaultBalance == 0) {
            // initialization, we consider the USDN price to be 1 USD
            return FixedPointMathLib.fullMulDiv(
                amount, price, 10 ** (_assetDecimals + _priceFeedDecimals - TOKENS_DECIMALS)
            );
        }
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalSupply, vaultBalance);
    }

    /**
     * @notice Get the lower 24 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares
     * @return sharesLSB_ The 24 least significant bits of the USDN shares
     */
    function _calcWithdrawalAmountLSB(uint152 usdnShares) internal pure returns (uint24 sharesLSB_) {
        sharesLSB_ = uint24(usdnShares);
    }

    /**
     * @notice Get the higher 128 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares
     * @return sharesMSB_ The 128 most significant bits of the USDN shares
     */
    function _calcWithdrawalAmountMSB(uint152 usdnShares) internal pure returns (uint128 sharesMSB_) {
        sharesMSB_ = uint128(usdnShares >> 24);
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `WithdrawalPendingAction`.
     * @param sharesLSB The lower 24 bits of the USDN shares
     * @param sharesMSB The higher bits of the USDN shares
     * @return usdnShares_ The amount of USDN shares
     */
    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        internal
        pure
        returns (uint256 usdnShares_)
    {
        usdnShares_ = sharesLSB | uint256(sharesMSB) << 24;
    }
}
