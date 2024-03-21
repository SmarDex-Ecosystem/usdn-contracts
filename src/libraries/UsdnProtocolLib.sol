// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import {
    PendingAction, VaultPendingAction, LongPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";

library UsdnProtocolLib {
    using SafeCast for uint256;
    using SignedMath for int256;

    /// @notice The number of decimals for leverage values
    uint8 public constant LEVERAGE_DECIMALS = 21;

    /// @notice The number of decimals for funding rate values
    uint8 public constant FUNDING_RATE_DECIMALS = 18;

    /// @notice The number of decimals for liquidation multiplier values
    uint8 public constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;

    /* -------------------------------------------------------------------------- */
    /*                                Storage layer                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Calculate the tickHash from a tick number and tick version
     * @param tick The tick number
     * @param version The tick version
     * @return tickHash_ the tick hash
     */
    function calcTickHash(int24 tick, uint256 version) external pure returns (bytes32 tickHash_) {
        tickHash_ = keccak256(abi.encodePacked(tick, version));
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Core layer                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Calculation of the EMA of the funding rate
     * @param lastFunding The last funding rate
     * @param secondsElapsed The number of seconds elapsed since the last protocol action
     * @param emaPeriod The EMA period
     * @param previousEMA The previous EMA
     * @return newEMA_ The updated EMA
     */
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        external
        pure
        returns (int256 newEMA_)
    {
        if (secondsElapsed >= emaPeriod) {
            return lastFunding;
        }

        newEMA_ = (lastFunding + previousEMA * toInt256(emaPeriod - secondsElapsed)) / toInt256(emaPeriod);
    }

    /**
     * @notice Calculate the new liquidation multiplier knowing the previous multiplier and funding
     * @param funding The funding
     * @param oldLiqMultiplier The old liquidation multiplier
     * @return newLiqMultiplier_ The new liquidation multiplier
     */
    function calcLiquidationMultiplier(int256 funding, uint256 oldLiqMultiplier)
        external
        pure
        returns (uint256 newLiqMultiplier_)
    {
        newLiqMultiplier_ = oldLiqMultiplier;

        // newMultiplier = oldMultiplier * (1 + funding)
        if (funding > 0) {
            newLiqMultiplier_ +=
                FixedPointMathLib.fullMulDiv(newLiqMultiplier_, uint256(funding), 10 ** FUNDING_RATE_DECIMALS);
        } else {
            newLiqMultiplier_ -=
                FixedPointMathLib.fullMulDiv(newLiqMultiplier_, uint256(-funding), 10 ** FUNDING_RATE_DECIMALS);
        }
    }

    /**
     * @notice Calculate the PnL in asset units of the long side, considering the overall total expo and change in
     * price.
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return pnl_ The profit or loss value in asset units
     */
    function calcPnlAsset(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        public
        pure
        returns (int256 pnl_)
    {
        int256 priceDiff = toInt256(newPrice) - toInt256(oldPrice);
        pnl_ = totalExpo.toInt256().safeSub(balanceLong.toInt256()).safeMul(priceDiff).safeDiv(toInt256(newPrice));
    }

    /**
     * @notice Convert a `PendingAction` to a `VaultPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted vault pending action
     */
    function toVaultPendingAction(PendingAction memory action)
        public
        pure
        returns (VaultPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `LongPendingAction`
     * @param action An untyped pending action
     * @return longAction_ The converted long pending action
     */
    function toLongPendingAction(PendingAction memory action)
        public
        pure
        returns (LongPendingAction memory longAction_)
    {
        assembly {
            longAction_ := action
        }
    }

    /**
     * @notice Convert a `VaultPendingAction` to a `PendingAction`
     * @param action A vault pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function convertVaultPendingAction(VaultPendingAction memory action)
        public
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `LongPendingAction` to a `PendingAction`
     * @param action A long pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function convertLongPendingAction(LongPendingAction memory action)
        public
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return available_ The balance of the long side
     */
    function calcLongAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        public
        pure
        returns (int256 available_)
    {
        // Avoid division by zero
        // slither-disable-next-line incorrect-equality
        if (totalExpo == 0) {
            return 0;
        }

        available_ = balanceLong.toInt256().safeAdd(calcPnlAsset(totalExpo, balanceLong, newPrice, oldPrice));
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account).
     * @param totalExpo the total expo
     * @param balanceVault the (old) balance of the vault
     * @param balanceLong the (old) balance of the long side
     * @param newPrice the new price
     * @param oldPrice the old price when the old balances were updated
     * @return available_ The available balance in the vault side
     */
    function calcVaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) external pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = calcLongAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);

        available_ = totalBalance.safeSub(newLongBalance);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Vault layer                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Calculate the price of the USDN token as a function of its total supply, the vault balance and the
     * underlying asset price.
     * @param vaultBalance The vault balance
     * @param assetPrice The price of the asset
     * @param usdnTotalSupply The total supply of the USDN token
     * @param usdnDecimals The number of decimals of the USDN token
     * @param assetDecimals The number of decimals of the underlying asset
     * @return price_ The price of the USDN token
     */
    function calcUsdnPrice(
        uint256 vaultBalance,
        uint128 assetPrice,
        uint256 usdnTotalSupply,
        uint8 usdnDecimals,
        uint8 assetDecimals
    ) external pure returns (uint256 price_) {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** usdnDecimals, usdnTotalSupply * 10 ** assetDecimals
        );
    }

    /**
     * @notice Calculate the required USDN total supply to reach `targetPrice`
     * @param vaultBalance The balance of the vault
     * @param assetPrice The price of the underlying asset
     * @param targetPrice The target USDN price to reach
     * @param usdnDecimals The number of decimals of the USDN token
     * @param assetDecimals The number of decimals of the asset
     * @return totalSupply_ The required total supply to achieve `targetPrice`
     */
    function calcRebaseTotalSupply(
        uint256 vaultBalance,
        uint128 assetPrice,
        uint128 targetPrice,
        uint8 usdnDecimals,
        uint8 assetDecimals
    ) external pure returns (uint256 totalSupply_) {
        totalSupply_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** usdnDecimals, uint256(targetPrice) * 10 ** assetDecimals
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Long layer                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the value of the lowest usable tick, taking into account the tick spacing
     * @dev Note that the effective minimum tick of a newly open long position also depends on the minimum allowed
     * leverage value and the current value of the liquidation price multiplier.
     * @param tickSpacing The tick spacing
     * @return tick_ The minimum tick
     */
    function calcMinTick(int24 tickSpacing) public pure returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(tickSpacing);
    }

    /**
     * @notice Get the value of the highest usable tick, taking into account the tick spacing
     * @dev Note that the effective maximum tick of a newly open long position also depends on the maximum allowed
     * leverage value and the current value of the liquidation price multiplier.
     * @param tickSpacing The tick spacing
     * @return tick_ The maximum tick
     */
    function calcMaxTick(int24 tickSpacing) public pure returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(tickSpacing);
    }

    /**
     * @notice Get the liquidation price corresponding to a given tick number
     * @dev This takes into account the liquidation price multiplier.
     * Note that ticks that are not a multiple of the tick spacing cannot contain a long position.
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier
     * @return price_ The effective price corresponding to a tick, taking the multiplier into account
     */
    function calcEffectivePriceForTick(int24 tick, uint256 liqMultiplier) external pure returns (uint128 price_) {
        // adjusted price with liquidation multiplier
        price_ = FixedPointMathLib.fullMulDiv(
            TickMath.getPriceAtTick(tick), liqMultiplier, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS
        ).toUint128();
    }

    /**
     * @notice Get the tick number corresponding to a given price
     * @dev This takes into account the liquidation price multiplier and the tick spacing
     * @param price The price
     * @param liqMultiplier The liquidation price multiplier
     * @param tickSpacing The tick spacing
     * @return tick_ The effective tick corresponding to a price, taking the multiplier and tick spacing into account
     */
    function calcEffectiveTickForPrice(uint128 price, uint256 liqMultiplier, int24 tickSpacing)
        public
        pure
        returns (int24 tick_)
    {
        // adjusted price with liquidation multiplier
        uint256 priceWithMultiplier =
            FixedPointMathLib.fullMulDiv(price, 10 ** UsdnProtocolLib.LIQUIDATION_MULTIPLIER_DECIMALS, liqMultiplier);

        if (priceWithMultiplier < TickMath.MIN_PRICE) {
            return calcMinTick(tickSpacing);
        }

        tick_ = TickMath.getTickAtPrice(priceWithMultiplier);

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick_ < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick_)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks
            int24 minUsableTick = calcMinTick(tickSpacing);
            if (tick_ < minUsableTick) {
                tick_ = minUsableTick;
            }
        } else {
            // rounding is desirable here
            // slither-disable-next-line divide-before-multiply
            tick_ = (tick_ / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Calculate the closest tick to a given price, taking into account the liquidation multiplier
     * @param currentPrice The current price of the asset
     * @param liqMultiplier The liquidation price multiplier
     * @return tick_ The closest tick to the given price
     */
    function calcClosestTickForPrice(uint256 currentPrice, uint256 liqMultiplier) external pure returns (int24 tick_) {
        tick_ = TickMath.getClosestTickAtPrice(
            FixedPointMathLib.fullMulDiv(
                currentPrice, 10 ** UsdnProtocolLib.LIQUIDATION_MULTIPLIER_DECIMALS, liqMultiplier
            )
        );
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @dev This does not take into account the liquidation penalty
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     * @return price_ The liquidation price of the position
     */
    function calcLiquidationPrice(uint128 startPrice, uint128 leverage) external pure returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    /**
     * @notice Calculate the value of a position, knowing its liquidation price and the current asset price
     * @param currentPrice The current price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     * @param positionTotalExpo The total expo of the position
     * @return value_ The value of the position
     */
    function calcPositionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (uint256 value_)
    {
        // Avoid an underflow
        if (currentPrice < liqPriceWithoutPenalty) {
            return 0;
        }

        value_ = FixedPointMathLib.fullMulDiv(positionTotalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice);
    }

    /**
     * @notice Calculate the initial leverage, knowing the start price of the position and the liquidation price
     * @dev This does not take into account the liquidation penalty
     * @param startPrice Entry price
     * @param liquidationPrice Liquidation price
     * @return leverage_ The initial leverage of the position
     */
    function calcLeverage(uint128 startPrice, uint128 liquidationPrice) external pure returns (uint128 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
    }

    /**
     * @notice Calculate the total exposure of a position
     * @dev Reverts when startPrice <= liquidationPrice
     * @param amount The amount of asset used as collateral
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return totalExpo_ The total exposure of a position
     */
    function calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
    {
        if (startPrice <= liquidationPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        totalExpo_ = FixedPointMathLib.fullMulDiv(amount, startPrice, startPrice - liquidationPrice).toUint128();
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Safely cast a uint128 to an int256
     * @param x The input unsigned integer
     * @return The value as a signed integer
     */
    function toInt256(uint128 x) public pure returns (int256) {
        return int256(uint256(x));
    }
}
