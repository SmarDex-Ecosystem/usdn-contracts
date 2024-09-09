// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";

/**
 * @title USDN Protocol Utils
 * @notice This library contains utility functions for the USDN protocol, and will not be deployed as an external lib
 * @dev All functions should be marked as "internal"
 */
library UsdnProtocolUtils {
    using SafeCast for uint256;
    using SignedMath for int256;

    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    /**
     * @notice Optimized position value calculation when `posTotalExpo` is known to be uint128 and `currentPrice` is
     * known to be above `liqPriceWithoutPenalty`
     * @param posTotalExpo The total expo of the position
     * @param currentPrice The current asset price
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @return posValue_ The value of the position, which must be positive
     */
    function positionValue(uint128 posTotalExpo, uint128 currentPrice, uint128 liqPriceWithoutPenalty)
        internal
        pure
        returns (uint256 posValue_)
    {
        // the multiplication cannot overflow because both operands are uint128
        posValue_ = uint256(posTotalExpo) * (currentPrice - liqPriceWithoutPenalty) / currentPrice;
    }

    /**
     * @notice Calculate the tick without the liquidation penalty
     * @param tick The tick that holds the position
     * @param liquidationPenalty The liquidation penalty of the tick, in number of ticks
     * @return tick_ The tick corresponding to the liquidation price without penalty
     */
    function calcTickWithoutPenalty(int24 tick, uint24 liquidationPenalty) internal pure returns (int24 tick_) {
        tick_ = tick - int24(liquidationPenalty);
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     * @return price_ The liquidation price of the position
     */
    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal pure returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** Constants.LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    /**
     * @notice Calculate the leverage of a position, knowing its start price and liquidation price
     * @dev This does not take into account the liquidation penalty
     * @param startPrice Entry price of the position
     * @param liquidationPrice Liquidation price of the position
     * @return leverage_ The leverage of the position
     */
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal pure returns (uint256 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // also, the calculation below would underflow
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = (10 ** Constants.LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice);
    }

    /**
     * @notice Convert a `Types.LongPendingAction` to a `Types.PendingAction`
     * @param action A long pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertLongPendingAction(Types.LongPendingAction memory action)
        internal
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.WithdrawalPendingAction` to a `Types.PendingAction`
     * @param action A withdrawal pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertWithdrawalPendingAction(Types.WithdrawalPendingAction memory action)
        internal
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.DepositPendingAction` to a `Types.PendingAction`
     * @param action A deposit pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertDepositPendingAction(Types.DepositPendingAction memory action)
        internal
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.PendingAction` to a `Types.LongPendingAction`
     * @param action An untyped pending action
     * @return longAction_ The converted long pending action
     */
    function _toLongPendingAction(Types.PendingAction memory action)
        internal
        pure
        returns (Types.LongPendingAction memory longAction_)
    {
        assembly {
            longAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.PendingAction` to a `Types.DepositPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted deposit pending action
     */
    function _toDepositPendingAction(Types.PendingAction memory action)
        internal
        pure
        returns (Types.DepositPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.PendingAction` to a `Types.WithdrawalPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted withdrawal pending action
     */
    function _toWithdrawalPendingAction(Types.PendingAction memory action)
        internal
        pure
        returns (Types.WithdrawalPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the tick spacing in storage
     * @param s The storage of the protocol
     * @param tick The tick to convert, a multiple of the tick spacing
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(Types.Storage storage s, int24 tick) internal view returns (uint256 index_) {
        index_ = _calcBitmapIndexFromTick(tick, s._tickSpacing);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the provided tick spacing
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @param tickSpacing The tick spacing to use
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) internal pure returns (uint256 index_) {
        index_ = uint256( // cast is safe as the min tick is always above TickMath.MIN_TICK
            (int256(tick) - TickMath.MIN_TICK) // shift into positive
                / tickSpacing
        );
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `Types.WithdrawalPendingAction`
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

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 available_)
    {
        // if balanceLong == totalExpo or the long trading expo is negative (theoretically impossible), the PnL is
        // zero
        // we can't calculate a proper PnL value if the long trading expo is negative because it would invert the
        // sign of the amount
        if (balanceLong >= totalExpo) {
            return balanceLong.toInt256();
        }
        int256 priceDiff = toInt256(newPrice) - toInt256(oldPrice);
        uint256 tradingExpo;
        // `balanceLong` is strictly inferior to `totalExpo`
        unchecked {
            tradingExpo = totalExpo - balanceLong;
        }
        int256 pnl = tradingExpo.toInt256().safeMul(priceDiff).safeDiv(toInt256(newPrice));

        available_ = balanceLong.toInt256().safeAdd(pnl);
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`
     * @param s The storage of the protocol
     * @param currentPrice The current price
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(Types.Storage storage s, uint128 currentPrice)
        internal
        view
        returns (int256 available_)
    {
        available_ = _longAssetAvailable(s._totalExpo, s._balanceLong, currentPrice, s._lastPrice);
    }
}
