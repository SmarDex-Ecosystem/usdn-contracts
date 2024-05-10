// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

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
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

abstract contract UsdnProtocolCommon is UsdnProtocolBaseStorage {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function _toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    /**
     * @notice Get the predicted value of the funding (in asset units) since the last state update for the given
     * timestamp
     * @dev If the provided timestamp is older than the last state update, the result will be zero
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fundingAsset_ The number of asset tokens of funding (with asset decimals)
     * @return fund_ The magnitude of the funding (with `FUNDING_RATE_DECIMALS` decimals)
     */
    function _fundingAsset(uint128 timestamp, int256 ema) internal view returns (int256 fundingAsset_, int256 fund_) {
        int256 oldLongExpo;
        (fund_, oldLongExpo) = _funding(timestamp, ema);
        fundingAsset_ = fund_.safeMul(oldLongExpo) / int256(10) ** s.FUNDING_RATE_DECIMALS;
    }

    /**
     * @notice Calculate the funding rate and the old long exposure
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fund_ The funding rate
     * @return oldLongExpo_ The old long exposure
     */
    function _funding(uint128 timestamp, int256 ema) internal view returns (int256 fund_, int256 oldLongExpo_) {
        oldLongExpo_ = s._totalExpo.toInt256().safeSub(s._balanceLong.toInt256());

        if (timestamp < s._lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
            // slither-disable-next-line incorrect-equality
        } else if (timestamp == s._lastUpdateTimestamp) {
            return (0, oldLongExpo_);
        }

        int256 oldVaultExpo = s._balanceVault.toInt256();

        // ImbalanceIndex = (longExpo - vaultExpo) / max(longExpo, vaultExpo)
        // fund = (sign(ImbalanceIndex) * ImbalanceIndex^2 * fundingSF) + _EMA
        // fund = (sign(ImbalanceIndex) * (longExpo - vaultExpo)^2 * fundingSF / denominator) + _EMA
        // with denominator = vaultExpo^2 if vaultExpo > longExpo, or longExpo^2 if longExpo > vaultExpo

        int256 numerator = oldLongExpo_ - oldVaultExpo;
        // optimization: if the numerator is zero, then return the EMA
        // slither-disable-next-line incorrect-equality
        if (numerator == 0) {
            return (ema, oldLongExpo_);
        }

        if (oldLongExpo_ <= 0) {
            // if oldLongExpo is negative, then we cap the imbalance index to -1
            // oldVaultExpo is always positive
            return (-int256(s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS)) + ema, oldLongExpo_);
        } else if (oldVaultExpo == 0) {
            // if oldVaultExpo is zero (can't be negative), then we cap the imbalance index to 1
            // oldLongExpo must be positive in this case
            return (int256(s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS)) + ema, oldLongExpo_);
        }

        // starting here, oldLongExpo and oldVaultExpo are always strictly positive

        uint256 elapsedSeconds = timestamp - s._lastUpdateTimestamp;
        uint256 numerator_squared = uint256(numerator * numerator);

        uint256 denominator;
        if (oldVaultExpo > oldLongExpo_) {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldVaultExpo * oldVaultExpo) * 1 days;
            fund_ = -int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        } else {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldLongExpo_ * oldLongExpo_) * 1 days;
            fund_ = int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    s._fundingSF * 10 ** (s.FUNDING_RATE_DECIMALS - s.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        }
    }

    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        pure
        returns (int256)
    {
        if (secondsElapsed >= emaPeriod) {
            return lastFunding;
        }

        return (lastFunding + previousEMA * _toInt256(emaPeriod - secondsElapsed)) / _toInt256(emaPeriod);
    }

    /**
     * @notice Function to calculate the hash and version of a given tick
     * @param tick The tick
     * @return hash_ The hash of the tick
     * @return version_ The version of the tick
     */
    function _tickHash(int24 tick) internal view returns (bytes32 hash_, uint256 version_) {
        version_ = s._tickVersion[tick];
        hash_ = tickHash(tick, version_);
    }

    /**
     * @notice Calculate the PnL in asset units of the long side, considering the overall total expo and change in
     * price
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return pnl_ The PnL in asset units
     */
    function _pnlAsset(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 pnl_)
    {
        // in case of a negative trading expo, we can't allow calculation of PnL because it would invert the sign of the
        // calculated amount. We thus disable any balance update due to PnL in such a case
        if (balanceLong >= totalExpo) {
            return 0;
        }
        int256 priceDiff = _toInt256(newPrice) - _toInt256(oldPrice);
        pnl_ = totalExpo.toInt256().safeSub(balanceLong.toInt256()).safeMul(priceDiff).safeDiv(_toInt256(newPrice));
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`
     * @param currentPrice The current price
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        available_ = _longAssetAvailable(s._totalExpo, s._balanceLong, currentPrice, s._lastPrice);
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
        // Avoid division by zero
        // slither-disable-next-line incorrect-equality
        if (totalExpo == 0) {
            return 0;
        }

        available_ = balanceLong.toInt256().safeAdd(_pnlAsset(totalExpo, balanceLong, newPrice, oldPrice));
    }
}
