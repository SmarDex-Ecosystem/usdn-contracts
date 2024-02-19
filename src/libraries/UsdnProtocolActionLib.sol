// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ProtocolAction, VaultPendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

/**
 * @title UsdnProtocolAction
 * @notice Perform USDN protocol actions.
 */
library UsdnProtocolActionLib {
    using SafeCast for uint256;

    function computePendingActionForInitialDeposit(
        uint128 amount,
        uint40 timestamp,
        uint256 lastPrice,
        uint256 protocolFee,
        uint256 PROTOCOL_FEE_DENOMINATOR,
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        IUsdn usdn
    ) external view returns (VaultPendingAction memory) {
        // Apply fees on price
        // we use `lastPrice` because it might be more recent than `currentPrice.price`
        uint256 pendingActionPrice = lastPrice;
        pendingActionPrice += (pendingActionPrice * protocolFee) / PROTOCOL_FEE_DENOMINATOR;

        VaultPendingAction memory pendingAction = VaultPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: timestamp,
            user: msg.sender,
            _unused: 0,
            amount: amount,
            assetPrice: pendingActionPrice.toUint128(),
            totalExpo: totalExpo,
            balanceVault: balanceVault,
            balanceLong: balanceLong,
            usdnTotalSupply: usdn.totalSupply()
        });

        return pendingAction;
    }

    function computeUsdnToMint(
        bool initializing,
        VaultPendingAction memory deposit,
        PriceInfo memory depositPrice_,
        uint256 priceWithFees,
        uint256 vaultAssetAvailable,
        uint256 assetDecimals,
        uint256 priceFeedDecimals,
        uint256 usdnDecimals
    ) external pure returns (uint256 usdnToMint) {
        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.

        // During initialization, the deposit.assetPrice is zero, so we use the price provided for validation.
        uint256 oldPrice = initializing ? depositPrice_.price : deposit.assetPrice;

        // The last parameter (price) is only used during initialization
        uint256 usdnToMint1 = _calcMintUsdn(
            deposit.amount,
            deposit.balanceVault,
            deposit.usdnTotalSupply,
            oldPrice,
            assetDecimals,
            priceFeedDecimals,
            usdnDecimals
        );
        uint256 usdnToMint2;
        {
            usdnToMint2 = _calcMintUsdn(
                deposit.amount,
                vaultAssetAvailable,
                deposit.usdnTotalSupply,
                // Price with fees (Inline calculation to avoid stack too deep)
                priceWithFees,
                assetDecimals,
                priceFeedDecimals,
                usdnDecimals
            );
        }
        if (usdnToMint1 <= usdnToMint2) {
            usdnToMint = usdnToMint1;
        } else {
            usdnToMint = usdnToMint2;
        }
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset
     * @param amount The amount of asset to be converted into USDN
     * @param vaultBalance The balance of the vault (not used for initialization)
     * @param usdnTotalSupply The total supply of USDN (not used for initialization)
     * @param price The price of the asset (only used for initialization)
     * @dev The amount of USDN to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance.
     */
    function _calcMintUsdn(
        uint256 amount,
        uint256 vaultBalance,
        uint256 usdnTotalSupply,
        uint256 price,
        uint256 _assetDecimals,
        uint256 _priceFeedDecimals,
        uint256 _usdnDecimals
    ) internal pure returns (uint256 toMint_) {
        if (vaultBalance == 0) {
            // initialization, we consider the USDN price to be 1 USD
            return
                FixedPointMathLib.fullMulDiv(amount, price, 10 ** (_assetDecimals + _priceFeedDecimals - _usdnDecimals));
        }
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalSupply, vaultBalance);
    }
}
