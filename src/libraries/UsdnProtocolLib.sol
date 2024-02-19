// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";

import { ProtocolAction, VaultPendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import {
    UsdnProtocolLibInvalidLiquidationPrice,
    UsdnProtocolLibLeverageTooLow,
    UsdnProtocolLibLeverageTooHigh
} from "src/libraries/UsdnProtocolLibErrors.sol";

/**
 * @title UsdnProtocol
 * @notice Helper to make the USDN protocol lighter.
 */
library UsdnProtocolLib {
    using SafeCast for uint256;
    using SignedMath for int256;

    /* -------------------------------------------------------------------------- */
    /*                                OPEN POSITION                               */
    /* -------------------------------------------------------------------------- */

    function computeLeverageTickAndPriceForOpenPosition(
        int24 desiredLiqTick,
        uint256 liqMultiplier,
        uint256 liqMultiplierDecimals,
        uint256 leverageDecimals,
        PriceInfo calldata currentPrice,
        uint24 liquidationPenalty,
        int24 tickSpacing,
        uint256 maxLeverage,
        uint256 minLeverage,
        uint256 protocolFee,
        uint256 protocolFeeDenominator
    ) external pure returns (uint128 leverage_, int24 tick_, uint256 price_) {
        // we calculate the closest valid tick down for the desired liq price without liquidation penalty
        uint128 liqPriceWithoutPenalty = _getEffectivePriceForTick(desiredLiqTick, liqMultiplier, liqMultiplierDecimals);

        price_ = currentPrice.price + (currentPrice.price * protocolFee) / protocolFeeDenominator;

        // calculate position leverage
        // reverts if liquidationPrice >= entryPrice
        // Inline calculation to avoid stack too deep
        leverage_ = _getLeverage(price_.toUint128(), liqPriceWithoutPenalty, leverageDecimals);
        if (leverage_ < minLeverage) {
            revert UsdnProtocolLibLeverageTooLow();
        }
        if (leverage_ > maxLeverage) {
            revert UsdnProtocolLibLeverageTooHigh();
        }

        // Apply liquidation penalty
        tick_ = desiredLiqTick + int24(liquidationPenalty) * tickSpacing;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  WITHDRAW                                  */
    /* -------------------------------------------------------------------------- */

    function computeAssetToTransfer(
        PriceInfo memory withdrawalPrice,
        VaultPendingAction memory withdrawal,
        uint256 protocolFee,
        uint256 PROTOCOL_FEE_DENOMINATOR
    ) external pure returns (uint256 assetToTransfer_) {
        // Apply fees on price
        uint256 withdrawalPriceWithFees =
            withdrawalPrice.price - (withdrawalPrice.price * protocolFee) / PROTOCOL_FEE_DENOMINATOR;

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.

        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = uint256(
            _vaultAssetAvailable(
                withdrawal.totalExpo,
                withdrawal.balanceVault,
                withdrawal.balanceLong,
                withdrawalPriceWithFees.toUint128(), // new price
                withdrawal.assetPrice // old price
            )
        );
        uint256 available;
        if (available1 <= available2) {
            available = available1;
        } else {
            available = available2;
        }

        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        assetToTransfer_ = FixedPointMathLib.fullMulDiv(withdrawal.amount, available, withdrawal.usdnTotalSupply);
    }

    function computePendingActionForInitialWithdrawal(
        uint128 usdnAmount,
        uint40 timestamp,
        uint256 lastPrice,
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        IUsdn usdn,
        uint256 protocolFee,
        uint256 PROTOCOL_FEE_DENOMINATOR
    ) external view returns (VaultPendingAction memory pendingAction_) {
        // Apply fees on price
        // we use `_lastPrice` because it might be more recent than `currentPrice.price`
        uint256 pendingActionPrice = lastPrice;
        pendingActionPrice -= (pendingActionPrice * protocolFee) / PROTOCOL_FEE_DENOMINATOR;

        pendingAction_ = VaultPendingAction({
            action: ProtocolAction.ValidateWithdrawal,
            timestamp: timestamp,
            user: msg.sender,
            _unused: 0,
            amount: usdnAmount,
            assetPrice: pendingActionPrice.toUint128(),
            totalExpo: totalExpo,
            balanceVault: balanceVault,
            balanceLong: balanceLong,
            usdnTotalSupply: usdn.totalSupply()
        });
    }

    /* -------------------------------------------------------------------------- */
    /*                                   DEPOSIT                                  */
    /* -------------------------------------------------------------------------- */

    function computePendingActionForInitialDeposit(
        uint128 amount,
        uint40 timestamp,
        uint256 lastPrice,
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        IUsdn usdn,
        uint256 protocolFee,
        uint256 PROTOCOL_FEE_DENOMINATOR
    ) external view returns (VaultPendingAction memory pendingAction_) {
        // Apply fees on price
        // we use `lastPrice` because it might be more recent than `currentPrice.price`
        uint256 pendingActionPrice = lastPrice;
        pendingActionPrice += (pendingActionPrice * protocolFee) / PROTOCOL_FEE_DENOMINATOR;

        pendingAction_ = VaultPendingAction({
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
    }

    function computeUsdnToMint(
        bool initializing,
        VaultPendingAction memory deposit,
        PriceInfo memory depositPrice_,
        uint256 assetDecimals,
        uint256 priceFeedDecimals,
        uint256 usdnDecimals,
        uint256 protocolFee,
        uint256 protocolFeeDenominator
    ) external pure returns (uint256 usdnToMint_) {
        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.

        // During initialization, the deposit.assetPrice is zero, so we use the price provided for validation.
        uint256 oldPrice = initializing ? depositPrice_.price : deposit.assetPrice;

        // Apply fees on price
        uint128 priceWithFees =
            (depositPrice_.price + (depositPrice_.price * protocolFee) / protocolFeeDenominator).toUint128();

        // Calculate the available balance in the vault side if the price moves to `priceWithFees`
        uint256 vaultAssetAvailable = uint256(
            _vaultAssetAvailable(
                deposit.totalExpo, deposit.balanceVault, deposit.balanceLong, priceWithFees, deposit.assetPrice
            )
        );

        // Comupute the amount of USDN to mint according to the deposit data
        uint256 usdnToMint1 = _calcMintUsdn(
            deposit.amount,
            deposit.balanceVault,
            deposit.usdnTotalSupply,
            oldPrice,
            assetDecimals,
            priceFeedDecimals,
            usdnDecimals
        );

        // Calculate the amount of USDN to mint using the storage data
        uint256 usdnToMint2 = _calcMintUsdn(
            deposit.amount,
            vaultAssetAvailable,
            deposit.usdnTotalSupply,
            priceWithFees,
            assetDecimals,
            priceFeedDecimals,
            usdnDecimals
        );

        // We use the lower of the two amounts to mint
        if (usdnToMint1 <= usdnToMint2) {
            usdnToMint_ = usdnToMint1;
        } else {
            usdnToMint_ = usdnToMint2;
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

    /* -------------------------------------------------------------------------- */
    /*                               PURE FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier, uint256 liqMultiplierDecimals)
        internal
        pure
        returns (uint128 price_)
    {
        // adjusted price with liquidation multiplier
        price_ = FixedPointMathLib.fullMulDiv(TickMath.getPriceAtTick(tick), liqMultiplier, 10 ** liqMultiplierDecimals)
            .toUint128();
    }

    /// @dev This does not take into account the liquidation penalty
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice, uint256 leverageDecimals)
        internal
        pure
        returns (uint128 leverage_)
    {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert UsdnProtocolLibInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** leverageDecimals * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account).
     * @param totalExpo the total expo
     * @param balanceVault the (old) balance of the vault
     * @param balanceLong the (old) balance of the long side
     * @param newPrice the new price
     * @param oldPrice the old price when the old balances were updated
     */
    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) internal pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = _longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);
        if (newLongBalance < 0) {
            newLongBalance = 0;
        }
        available_ = totalBalance.safeSub(newLongBalance);
        if (available_ < 0) {
            available_ = 0;
        }
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     */
    function _longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 available_)
    {
        // Avoid division by zero
        // slither-disable-next-line incorrect-equality
        if (totalExpo == 0) {
            return 0;
        }

        available_ = balanceLong.toInt256().safeAdd(_pnlAsset(totalExpo, balanceLong, newPrice, oldPrice));
    }

    /**
     * @notice Calculate the PnL in asset units of the long side, considering the overall total expo and change in
     * price.
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     */
    function _pnlAsset(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 pnl_)
    {
        int256 priceDiff = _toInt256(newPrice) - _toInt256(oldPrice);
        pnl_ = totalExpo.toInt256().safeSub(balanceLong.toInt256()).safeMul(priceDiff).safeDiv(_toInt256(newPrice));
    }

    function _toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }
}
