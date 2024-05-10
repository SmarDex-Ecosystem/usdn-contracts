// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position, LiquidationsEffects, TickData, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import {
    Position,
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    LiquidationsEffects,
    PreviousActionsData,
    PositionId,
    TickData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolCommon } from "src/UsdnProtocol/UsdnProtocolCommon.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

abstract contract UsdnProtocolLongProxy is UsdnProtocolCommon {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    function maxTick() public view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(s._tickSpacing);
    }

    function getLongPosition(PositionId memory posId)
        public
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        (bytes32 tickHash, uint256 version) = _tickHash(posId.tick);
        if (posId.tickVersion != version) {
            revert UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        pos_ = s._longPositions[tickHash][posId.index];
        liquidationPenalty_ = s._tickData[tickHash].liquidationPenalty;
    }

    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) public view returns (uint128 liquidationPrice_) {
        liquidationPrice_ = _getLiquidationPrice(price, uint128(s._minLeverage));
        int24 tick = getEffectiveTickForPrice(liquidationPrice_);
        liquidationPrice_ = getEffectivePriceForTick(tick + s._tickSpacing);
    }

    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        (Position memory pos, uint8 liquidationPenalty) = getLongPosition(posId);
        int256 longTradingExpo = longTradingExpoWithFunding(price, timestamp);
        if (longTradingExpo < 0) {
            // In case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // In this case, the liquidation price will fall to zero, and the position value will be equal to its
            // total expo (initial collateral * initial leverage).
            longTradingExpo = 0;
        }
        uint128 liqPrice = getEffectivePriceForTick(
            _calcTickWithoutPenalty(posId.tick, liquidationPenalty),
            price,
            uint256(longTradingExpo),
            s._liqMultiplierAccumulator
        );
        value_ = _positionValue(price, liqPrice, pos.totalExpo);
    }

    /**
     * @notice Calculate a fixed-precision representation of the liquidation price multiplier
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return multiplier_ The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     */
    function _calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal view returns (uint256 multiplier_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return 10 ** s.LIQUIDATION_MULTIPLIER_DECIMALS;
        }
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator =
            HugeUint.mul(10 ** s.LIQUIDATION_MULTIPLIER_DECIMALS, assetPrice * longTradingExpo);
        multiplier_ = numerator.div(accumulator);
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = (currentPrice * (s.BPS_DIVISOR - s._safetyMarginBps) / s.BPS_DIVISOR).toUint128();
        if (liquidationPrice >= maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public view returns (int256 expo_) {
        expo_ = s._totalExpo.toInt256().safeSub(longAssetAvailableWithFunding(currentPrice, timestamp));
    }

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
        }

        int256 ema = calcEMA(s._lastFunding, timestamp - s._lastUpdateTimestamp, s._EMAPeriod, s._EMA);
        (int256 fundAsset,) = _fundingAsset(timestamp, ema);

        if (fundAsset > 0) {
            available_ = _longAssetAvailable(currentPrice).safeSub(fundAsset);
        } else {
            int256 fee = fundAsset * _toInt256(s._protocolFeeBps) / int256(s.BPS_DIVISOR);
            // fees have the same sign as fundAsset (negative here), so we need to sub them
            available_ = _longAssetAvailable(currentPrice).safeSub(fundAsset - fee);
        }
    }
}
