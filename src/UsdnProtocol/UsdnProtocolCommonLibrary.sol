// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";

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
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { Storage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { UsdnProtocolActionsLibrary as actionsLib } from "src/UsdnProtocol/UsdnProtocolActionsLibrary.sol";

library UsdnProtocolCommonLibrary {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /**
     * @notice Emitted when the pending protocol fee is distributed
     * @param feeCollector The collector address
     * @param amount The amount of fee transferred
     */
    event ProtocolFeeDistributed(address feeCollector, uint256 amount);

    /**
     * @notice Emitted when a user (liquidator) successfully liquidated positions
     * @param liquidator The address that initiated the liquidation
     * @param rewards The amount of tokens the liquidator received in rewards
     */
    event LiquidatorRewarded(address indexed liquidator, uint256 rewards);

    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function _toInt256(uint128 x) public pure returns (int256) {
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
    function _fundingAsset(Storage storage s, uint128 timestamp, int256 ema)
        public
        view
        returns (int256 fundingAsset_, int256 fund_)
    {
        int256 oldLongExpo;
        (fund_, oldLongExpo) = _funding(s, timestamp, ema);
        fundingAsset_ = fund_.safeMul(oldLongExpo) / int256(10) ** s.FUNDING_RATE_DECIMALS;
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
    function _tickHash(Storage storage s, int24 tick) public view returns (bytes32 hash_, uint256 version_) {
        version_ = s._tickVersion[tick];
        hash_ = calcTickHash(tick, version_);
    }

    function calcTickHash(int24 tick, uint256 version) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
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
        public
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
    function _longAssetAvailable(Storage storage s, uint128 currentPrice) public view returns (int256 available_) {
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
        public
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
     * @notice Refunds any excess ether to the user to prevent locking ETH in the contract.
     * @param securityDepositValue The security deposit value of the action (zero for a validation action).
     * @param amountToRefund The amount to refund to the user:
     *      - the security deposit if executing an action for another user,
     *      - the initialization security deposit in case of a validation action.
     * @param balanceBefore The balance of the contract before the action.
     */
    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore) external {
        uint256 positive = amountToRefund + address(this).balance + msg.value;
        uint256 negative = balanceBefore + securityDepositValue;

        if (negative > positive) {
            revert IUsdnProtocolErrors.UsdnProtocolUnexpectedBalance();
        }

        uint256 amount;
        unchecked {
            // we know that positive >= negative, so this subtraction is safe
            amount = positive - negative;
        }

        if (amount != 0) {
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = payable(msg.sender).call{ value: amount }("");
            if (!success) {
                revert IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed();
            }
        }
    }

    function _checkPendingFee(Storage storage s) external {
        // if the pending protocol fee is above the threshold, send it to the fee collector
        if (s._pendingProtocolFee >= s._feeThreshold) {
            s._asset.safeTransfer(s._feeCollector, s._pendingProtocolFee);
            emit ProtocolFeeDistributed(s._feeCollector, s._pendingProtocolFee);
            s._pendingProtocolFee = 0;
        }
    }

    /**
     * @notice Variant of `getEffectivePriceForTick` when a fixed precision representation of the liquidation
     * multiplier
     * is known
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _getEffectivePriceForTick(Storage storage s, int24 tick, uint256 liqMultiplier)
        public
        view
        returns (uint128 price_)
    {
        price_ = _adjustPrice(s, TickMath.getPriceAtTick(tick), liqMultiplier);
    }

    /**
     * @notice Calculate the value of a position, knowing its liquidation price and the current asset price
     * @param currentPrice The current price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     * @param positionTotalExpo The total expo of the position
     * @return value_ The value of the position. If the current price is smaller than the liquidation price without
     * penalty, then the position value is negative (bad debt)
     */
    function _positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        public
        pure
        returns (int256 value_)
    {
        if (currentPrice < liqPriceWithoutPenalty) {
            value_ = -FixedPointMathLib.fullMulDiv(positionTotalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice)
                .toInt256();
        } else {
            value_ = FixedPointMathLib.fullMulDiv(
                positionTotalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice
            ).toInt256();
        }
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     */
    function _getLiquidationPrice(Storage storage s, uint128 startPrice, uint128 leverage)
        public
        view
        returns (uint128 price_)
    {
        price_ = (startPrice - ((uint256(10) ** s.LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    function getEffectiveTickForPrice(Storage storage s, uint128 price) public view returns (int24 tick_) {
        tick_ = getEffectiveTickForPrice(
            price, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator, s._tickSpacing
        );
    }

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) public pure returns (int24 tick_) {
        // unadjust price with liquidation multiplier
        uint256 unadjustedPrice = _unadjustPrice(price, assetPrice, longTradingExpo, accumulator);

        if (unadjustedPrice < TickMath.MIN_PRICE) {
            return TickMath.minUsableTick(tickSpacing);
        }

        tick_ = TickMath.getTickAtPrice(unadjustedPrice);

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick_ < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick_)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks
            int24 minUsableTick = TickMath.minUsableTick(tickSpacing);
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
     * @notice Remove the provided total amount from its position and update the tick data and position
     * @dev Note: this method does not update the long balance
     * If the amount to remove is greater than or equal to the position's total amount, the position is deleted
     * instead
     * @param tick The tick to remove from
     * @param index Index of the position in the tick array
     * @param pos The position to remove the amount from
     * @param amountToRemove The amount to remove from the position
     * @param totalExpoToRemove The total expo to remove from the position
     */
    function _removeAmountFromPosition(
        Storage storage s,
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) public {
        (bytes32 tickHash,) = _tickHash(s, tick);
        TickData storage tickData = s._tickData[tickHash];
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
        if (amountToRemove < pos.amount) {
            Position storage position = s._longPositions[tickHash][index];
            position.totalExpo = pos.totalExpo - totalExpoToRemove;

            unchecked {
                position.amount = pos.amount - amountToRemove;
            }
        } else {
            totalExpoToRemove = pos.totalExpo;
            tickData.totalPos -= 1;
            --s._totalLongPositions;

            // Remove from tick array (set to zero to avoid shifting indices)
            delete s._longPositions[tickHash][index];
            if (tickData.totalPos == 0) {
                // we removed the last position in the tick
                s._tickBitmap.unset(_calcBitmapIndexFromTick(s, tick));
            }
        }

        s._totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
        s._liqMultiplierAccumulator =
            s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * totalExpoToRemove));
    }

    function getTickLiquidationPenalty(Storage storage s, int24 tick) public view returns (uint8 liquidationPenalty_) {
        (bytes32 tickHash,) = _tickHash(s, tick);
        liquidationPenalty_ = _getTickLiquidationPenalty(s, tickHash);
    }

    /**
     * @notice Retrieve the liquidation penalty assigned to the tick and version corresponding to `tickHash`, if
     * there
     * are positions in it, otherwise retrieve the current setting value from storage.
     * @dev This method allows to re-use a pre-computed tickHash if available
     * @param tickHash The tick hash
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function _getTickLiquidationPenalty(Storage storage s, bytes32 tickHash)
        public
        view
        returns (uint8 liquidationPenalty_)
    {
        TickData storage tickData = s._tickData[tickHash];
        liquidationPenalty_ = tickData.totalPos != 0 ? tickData.liquidationPenalty : s._liquidationPenalty;
    }

    /**
     * @notice Save a new position in the protocol, adjusting the tick data and global variables
     * @dev Note: this method does not update the long balance
     * @param tick The tick to hold the new position
     * @param long The position to save
     * @param liquidationPenalty The liquidation penalty for the tick
     */
    function _saveNewPosition(Storage storage s, int24 tick, Position memory long, uint8 liquidationPenalty)
        public
        returns (uint256 tickVersion_, uint256 index_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = _tickHash(s, tick);

        // Add to tick array
        Position[] storage tickArray = s._longPositions[tickHash];
        index_ = tickArray.length;
        if (tick > s._highestPopulatedTick) {
            // keep track of the highest populated tick
            s._highestPopulatedTick = tick;
        }
        tickArray.push(long);

        // Adjust state
        s._totalExpo += long.totalExpo;
        ++s._totalLongPositions;

        // Update tick data
        TickData storage tickData = s._tickData[tickHash];
        // The unadjusted tick price for the accumulator might be different depending if we already have positions in
        // the tick or not
        uint256 unadjustedTickPrice;
        if (tickData.totalPos == 0) {
            // first position in this tick, we need to reflect that it is populated
            s._tickBitmap.set(_calcBitmapIndexFromTick(s, tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
            unadjustedTickPrice = TickMath.getPriceAtTick(tick - int24(uint24(liquidationPenalty)) * s._tickSpacing);
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's liquidationPenalty since it remains constant
            unadjustedTickPrice =
                TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
        }
        // Update the accumulator with the correct tick price (depending on the liquidation penalty value)
        s._liqMultiplierAccumulator =
            s._liqMultiplierAccumulator.add(HugeUint.wrap(unadjustedTickPrice * long.totalExpo));
    }

    /**
     * @notice Calculate the total exposure of a position
     * @dev Reverts when startPrice <= liquidationPrice
     * @param amount The amount of asset used as collateral
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return totalExpo_ The total exposure of a position
     */
    function _calculatePositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        public
        pure
        returns (uint128 totalExpo_)
    {
        if (startPrice <= liquidationPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        totalExpo_ = FixedPointMathLib.fullMulDiv(amount, startPrice, startPrice - liquidationPrice).toUint128();
    }

    function getEffectivePriceForTick(Storage storage s, int24 tick) public view returns (uint128 price_) {
        price_ =
            getEffectivePriceForTick(tick, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator);
    }

    /// @dev This does not take into account the liquidation penalty
    function _getLeverage(Storage storage s, uint128 startPrice, uint128 liquidationPrice)
        public
        view
        returns (uint128 leverage_)
    {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** s.LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `WithdrawalPendingAction`.
     * @param sharesLSB The lower 24 bits of the USDN shares
     * @param sharesMSB The higher bits of the USDN shares
     * @return usdnShares_ The amount of USDN shares
     */
    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        public
        pure
        returns (uint256 usdnShares_)
    {
        usdnShares_ = sharesLSB | uint256(sharesMSB) << 24;
    }

    /**
     * @notice Calculate the amount of assets received when burning USDN shares
     * @param usdnShares The amount of USDN shares
     * @param available The available asset in the vault
     * @param usdnTotalShares The total supply of USDN shares
     * @return assetExpected_ The expected amount of asset to be received
     */
    function _calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        public
        pure
        returns (uint256 assetExpected_)
    {
        // assetExpected = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        //                 = shares * assetAvailable / usdnTotalShares
        assetExpected_ = FixedPointMathLib.fullMulDiv(usdnShares, available, usdnTotalShares);
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
    function _calcMintUsdn(
        Storage storage s,
        uint256 amount,
        uint256 vaultBalance,
        uint256 usdnTotalSupply,
        uint256 price
    ) public view returns (uint256 toMint_) {
        if (vaultBalance == 0) {
            // initialization, we consider the USDN price to be 1 USD
            return FixedPointMathLib.fullMulDiv(
                amount, price, 10 ** (s._assetDecimals + s._priceFeedDecimals - s.TOKENS_DECIMALS)
            );
        }
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalSupply, vaultBalance);
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param totalExpo The total expo
     * @param balanceVault The (old) balance of the vault
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balances were updated
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) public pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = _longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);

        available_ = totalBalance.safeSub(newLongBalance);
    }

    function _getOraclePrice(Storage storage s, ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        public
        returns (PriceInfo memory price_)
    {
        uint256 validationCost = s._oracleMiddleware.validationCost(priceData, action);
        if (address(this).balance < validationCost) {
            revert IUsdnProtocolErrors.UsdnProtocolInsufficientOracleFee();
        }
        price_ =
            s._oracleMiddleware.parseAndValidatePrice{ value: validationCost }(uint128(timestamp), action, priceData);
    }

    /**
     * @notice Applies PnL, funding, and liquidates positions if necessary.
     * @param neutralPrice The neutral price for the asset.
     * @param timestamp The timestamp at which the operation is performed.
     * @param iterations The number of iterations for the liquidation process.
     * @param ignoreInterval A boolean indicating whether to ignore the interval for USDN rebase.
     * @param priceData The price oracle update data.
     * @return liquidatedPositions_ The number of positions that were liquidated.
     * @dev If there were any liquidated positions, it sends rewards to the msg.sender.
     */
    function _applyPnlAndFundingAndLiquidate(
        Storage storage s,
        uint256 neutralPrice,
        uint256 timestamp,
        uint16 iterations,
        bool ignoreInterval,
        bytes memory priceData
    ) public returns (uint256 liquidatedPositions_) {
        // adjust balances
        (bool priceUpdated, int256 tempLongBalance, int256 tempVaultBalance) =
            _applyPnlAndFunding(s, neutralPrice.toUint128(), timestamp.toUint128());

        // liquidate if price is more recent than _lastPrice
        if (priceUpdated) {
            LiquidationsEffects memory liquidationEffects =
                actionsLib._liquidatePositions(s, neutralPrice, iterations, tempLongBalance, tempVaultBalance);

            s._balanceLong = liquidationEffects.newLongBalance;
            s._balanceVault = liquidationEffects.newVaultBalance;

            bool rebased = _usdnRebase(s, uint128(neutralPrice), ignoreInterval); // safecast not needed since already
                // done
                // earlier

            if (liquidationEffects.liquidatedTicks > 0) {
                _sendRewardsToLiquidator(
                    s, liquidationEffects.liquidatedTicks, liquidationEffects.remainingCollateral, rebased, priceData
                );
            }

            liquidatedPositions_ = liquidationEffects.liquidatedPositions;
        }
    }

    /**
     * @notice Knowing the liquidation price of a position, get the corresponding unadjusted price, which can be used
     * to find the corresponding tick.
     * @param price An adjusted liquidation price (taking into account the effects of funding)
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return unadjustedPrice_ The unadjusted price for the liquidation price
     */
    function _unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint256 unadjustedPrice_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return price;
        }
        if (longTradingExpo == 0) {
            // it is not possible to calculate the unadjusted price when the trading expo is zero
            revert IUsdnProtocolErrors.UsdnProtocolZeroLongTradingExpo();
        }
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        // unadjustedPrice = price / M
        // unadjustedPrice = price * accumulator / (assetPrice * (totalExpo - balanceLong))
        HugeUint.Uint512 memory numerator = accumulator.mul(price);
        unadjustedPrice_ = numerator.div(assetPrice * longTradingExpo);
    }

    /**
     * @notice Calculate the value of a tick, knowing its contained total expo and the current asset price
     * @param tick The tick number
     * @param currentPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side
     * @param accumulator The liquidation multiplier accumulator
     * @param tickData The aggregate data for the tick
     * @return value_ The value of the tick (qty of asset tokens)
     */
    function _tickValue(
        Storage storage s,
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) public view returns (int256 value_) {
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(
            _calcTickWithoutPenalty(s, tick, tickData.liquidationPenalty), currentPrice, longTradingExpo, accumulator
        );

        // value = totalExpo * (currentPrice - liqPriceWithoutPenalty) / currentPrice
        // if the current price is lower than the liquidation price, we have effectively a negative value
        if (currentPrice <= liqPriceWithoutPenalty) {
            // we calculate the inverse and then change the sign
            value_ = -int256(
                FixedPointMathLib.fullMulDiv(tickData.totalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice)
            );
        } else {
            value_ = int256(
                FixedPointMathLib.fullMulDiv(tickData.totalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice)
            );
        }
    }

    /**
     * @notice Calculate the tick without the liquidation penalty
     * @param tick The tick that holds the position
     * @param liquidationPenalty The liquidation penalty of the tick
     * @return tick_ The tick corresponding to the liquidation price without penalty
     */
    function _calcTickWithoutPenalty(Storage storage s, int24 tick, uint8 liquidationPenalty)
        public
        view
        returns (int24 tick_)
    {
        tick_ = tick - int24(uint24(liquidationPenalty)) * s._tickSpacing;
    }

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), assetPrice, longTradingExpo, accumulator);
    }

    /**
     * @notice Knowing the unadjusted price for a tick, get the adjusted price taking into account the effects of the
     * funding.
     * @param unadjustedPrice The unadjusted price for the tick
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return price_ The adjusted price for the tick
     */
    function _adjustPrice(
        uint256 unadjustedPrice,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return unadjustedPrice.toUint128();
        }

        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        // price = unadjustedPrice * M
        // price = unadjustedPrice * assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator = HugeUint.mul(unadjustedPrice, assetPrice * longTradingExpo);
        price_ = numerator.div(accumulator).toUint128();
    }

    /**
     * @notice Find the highest tick that contains at least one position
     * @dev If there are no ticks with a position left, returns minTick()
     * @param searchStart The tick from which to start searching
     * @return tick_ The next highest tick below `searchStart`
     */
    function _findHighestPopulatedTick(Storage storage s, int24 searchStart) public view returns (int24 tick_) {
        uint256 index = s._tickBitmap.findLastSet(_calcBitmapIndexFromTick(s, searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick(s);
        } else {
            tick_ = _calcTickFromBitmapIndex(s, index);
        }
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the tick spacing in storage
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of the tick spacing
     */
    function _calcTickFromBitmapIndex(Storage storage s, uint256 index) public view returns (int24 tick_) {
        tick_ = _calcTickFromBitmapIndex(index, s._tickSpacing);
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the provided tick spacing
     * @param index The index into the Bitmap
     * @param tickSpacing The tick spacing to use
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
     */
    function _calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) public pure returns (int24 tick_) {
        tick_ = int24( // cast to int24 is safe as index + TickMath.MIN_TICK cannot be above or below int24 limits
            (
                int256(index) // cast to int256 is safe as the index is lower than type(int24).max
                    + TickMath.MIN_TICK // shift into negative
                        / tickSpacing
            ) * tickSpacing
        );
    }

    function minTick(Storage storage s) public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(s._tickSpacing);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the tick spacing in storage
     * @param tick The tick to convert, a multiple of the tick spacing
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(Storage storage s, int24 tick) public view returns (uint256 index_) {
        index_ = _calcBitmapIndexFromTick(tick, s._tickSpacing);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the provided tick spacing
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @param tickSpacing The tick spacing to use
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) public pure returns (uint256 index_) {
        index_ = uint256( // cast is safe as the min tick is always above TickMath.MIN_TICK
            (int256(tick) - TickMath.MIN_TICK) // shift into positive
                / tickSpacing
        );
    }

    /**
     * @notice Handle negative balances by transferring assets from one side to the other
     * @dev Balances are unsigned integers and can't be negative
     * In theory, this can not happen anymore because we have more precise calculations with the
     * `liqMultiplierAccumulator` compared to the old `liquidationMultiplier`
     * TODO: check if can be removed
     * @param tempLongBalance The temporary long balance after liquidations
     * @param tempVaultBalance The temporary vault balance after liquidations
     * @return longBalance_ The new long balance after rebalancing
     * @return vaultBalance_ The new vault balance after rebalancing
     */
    function _handleNegativeBalances(int256 tempLongBalance, int256 tempVaultBalance)
        public
        pure
        returns (uint256 longBalance_, uint256 vaultBalance_)
    {
        // This can happen if the funding is larger than the remaining balance in the long side after applying PnL.
        // Test case: test_assetToTransferZeroBalance()
        if (tempLongBalance < 0) {
            tempVaultBalance += tempLongBalance;
            tempLongBalance = 0;
        }

        // This can happen if there is not enough balance in the vault to pay the bad debt of the long side, for
        // example if the protocol fees reduce the vault balance.
        // Test case: test_funding_NegLong_ZeroVault()
        if (tempVaultBalance < 0) {
            tempLongBalance += tempVaultBalance;
            tempVaultBalance = 0;
        }

        // TODO: remove safe cast once we're sure we can never have negative balances
        longBalance_ = tempLongBalance.toUint256();
        vaultBalance_ = tempVaultBalance.toUint256();
    }

    /**
     * @notice Check if a USDN rebase is required and adjust divisor if needed.
     * @dev Note: only call this function after `_applyPnlAndFunding` has been called to update the balances.
     * @param assetPrice The current price of the underlying asset
     * @param ignoreInterval If true, then the price check will be performed regardless of when the last check
     * happened
     * @return rebased_ Whether a rebase was performed
     */
    function _usdnRebase(Storage storage s, uint128 assetPrice, bool ignoreInterval) public returns (bool rebased_) {
        if (!ignoreInterval && block.timestamp - s._lastRebaseCheck < s._usdnRebaseInterval) {
            return false;
        }
        s._lastRebaseCheck = block.timestamp;
        IUsdn usdn = s._usdn;
        uint256 divisor = usdn.divisor();
        if (divisor <= s._usdnMinDivisor) {
            // no need to rebase, the USDN divisor cannot go lower
            return false;
        }
        uint256 balanceVault = s._balanceVault;
        uint8 assetDecimals = s._assetDecimals;
        uint256 usdnTotalSupply = usdn.totalSupply();
        uint256 uPrice = _calcUsdnPrice(s, balanceVault, assetPrice, usdnTotalSupply, assetDecimals);
        if (uPrice <= s._usdnRebaseThreshold) {
            return false;
        }
        uint256 targetTotalSupply =
            _calcRebaseTotalSupply(s, balanceVault, assetPrice, s._targetUsdnPrice, assetDecimals);
        uint256 newDivisor = FixedPointMathLib.fullMulDiv(usdnTotalSupply, divisor, targetTotalSupply);
        usdn.rebase(newDivisor);
        rebased_ = true;
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
    function _calcUsdnPrice(
        Storage storage s,
        uint256 vaultBalance,
        uint128 assetPrice,
        uint256 usdnTotalSupply,
        uint8 assetDecimals
    ) public view returns (uint256 price_) {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** s.TOKENS_DECIMALS, usdnTotalSupply * 10 ** assetDecimals
        );
    }

    /**
     * @notice Calculate the required USDN total supply to reach `targetPrice`
     * @param vaultBalance The balance of the vault
     * @param assetPrice The price of the underlying asset
     * @param targetPrice The target USDN price to reach
     * @param assetDecimals The number of decimals of the asset
     * @return totalSupply_ The required total supply to achieve `targetPrice`
     */
    function _calcRebaseTotalSupply(
        Storage storage s,
        uint256 vaultBalance,
        uint128 assetPrice,
        uint128 targetPrice,
        uint8 assetDecimals
    ) public view returns (uint256 totalSupply_) {
        totalSupply_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** s.TOKENS_DECIMALS, uint256(targetPrice) * 10 ** assetDecimals
        );
    }

    /**
     * @notice Send rewards to the liquidator.
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain.
     * @param liquidatedTicks The number of ticks that were liquidated.
     * @param remainingCollateral The amount of collateral remaining after liquidations.
     * @param rebased Whether a USDN rebase was performed.
     * @param priceData The price oracle update data.
     */
    function _sendRewardsToLiquidator(
        Storage storage s,
        uint16 liquidatedTicks,
        int256 remainingCollateral,
        bool rebased,
        bytes memory priceData
    ) public {
        // Get how much we should give to the liquidator as rewards
        uint256 liquidationRewards =
            s._liquidationRewardsManager.getLiquidationRewards(liquidatedTicks, remainingCollateral, rebased, priceData);

        // Avoid underflows in situation of extreme bad debt
        if (s._balanceVault < liquidationRewards) {
            liquidationRewards = s._balanceVault;
        }

        // Update the vault's balance
        unchecked {
            s._balanceVault -= liquidationRewards;
        }

        // Transfer rewards (wsteth) to the liquidator
        s._asset.safeTransfer(msg.sender, liquidationRewards);

        emit LiquidatorRewarded(msg.sender, liquidationRewards);
    }

    struct ApllyPnlAndFundingData {
        uint128 lastUpdateTimestamp;
        int256 ema;
        int256 fundAsset;
        int256 fund;
        int256 fee;
        int256 fundWithFee;
        int256 fundAssetWithFee;
    }

    /**
     * @notice Calculate the profits and losses of the long side, calculate the funding and apply protocol fees,
     * calculate the new liquidation multiplier and the temporary new balances for each side
     * @dev This function updates the state of `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding`, but does not
     * update the balances. This is left to the caller
     * @param currentPrice The current price
     * @param timestamp The timestamp of the current price
     * @return priceUpdated_ Whether the price was updated
     * @return tempLongBalance_ The new balance of the long side, could be negative (temporarily)
     * @return tempVaultBalance_ The new balance of the vault side, could be negative (temporarily)
     */
    function _applyPnlAndFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        returns (bool priceUpdated_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        ApllyPnlAndFundingData memory data;
        // cache variable for optimization
        data.lastUpdateTimestamp = s._lastUpdateTimestamp;
        // if the price is not fresh, do nothing
        if (timestamp <= data.lastUpdateTimestamp) {
            return (false, s._balanceLong.toInt256(), s._balanceVault.toInt256());
        }

        // update the funding EMA
        data.ema = _updateEMA(s, timestamp - data.lastUpdateTimestamp);

        // calculate the funding
        (data.fundAsset, data.fund) = _fundingAsset(s, timestamp, data.ema);

        // take protocol fee on the funding value
        (data.fee, data.fundWithFee, data.fundAssetWithFee) = _calculateFee(s, data.fund, data.fundAsset);

        // we subtract the fee from the total balance
        int256 totalBalance = s._balanceLong.toInt256().safeAdd(s._balanceVault.toInt256()).safeSub(data.fee);
        // calculate new balances (for now, any bad debt has not been repaid, balances could become negative)

        if (data.fund > 0) {
            // in case of positive funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the vault balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(s, currentPrice).safeSub(data.fundAsset);
        } else {
            // in case of negative funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the long balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(s, currentPrice).safeSub(data.fundAssetWithFee);
        }
        tempVaultBalance_ = totalBalance.safeSub(tempLongBalance_);

        // update state variables
        s._lastPrice = currentPrice;
        s._lastUpdateTimestamp = timestamp;
        s._lastFunding = data.fundWithFee;

        priceUpdated_ = true;
    }

    /**
     * @notice Calculate the protocol fee and apply it to the funding asset amount
     * @dev The funding factor is only adjusted by the fee rate when the funding is negative (vault pays to the long
     * side)
     * @param fund The funding factor
     * @param fundAsset The funding asset amount to be used for the fee calculation
     * @return fee_ The absolute value of the calculated fee
     * @return fundWithFee_ The updated funding factor after applying the fee
     * @return fundAssetWithFee_ The updated funding asset amount after applying the fee
     */
    function _calculateFee(Storage storage s, int256 fund, int256 fundAsset)
        public
        returns (int256 fee_, int256 fundWithFee_, int256 fundAssetWithFee_)
    {
        int256 protocolFeeBps = _toInt256(s._protocolFeeBps);
        fundWithFee_ = fund;
        fee_ = fundAsset * protocolFeeBps / int256(s.BPS_DIVISOR);
        // fundAsset and fee_ have the same sign, we can safely subtract them to reduce the absolute amount of asset
        fundAssetWithFee_ = fundAsset - fee_;

        if (fee_ < 0) {
            // when funding is negative, the part that is taken as fees does not contribute to the liquidation
            // multiplier adjustment, and so we should deduce it from the funding factor
            fundWithFee_ -= fund * protocolFeeBps / int256(s.BPS_DIVISOR);
            // we want to return the absolute value of the fee
            fee_ = -fee_;
        }

        s._pendingProtocolFee += uint256(fee_);
    }

    /**
     * @notice Update the Exponential Moving Average (EMA) of the funding
     * @dev This function is called every time the protocol state is updated
     * @dev All required checks are done in the caller function (_applyPnlAndFunding)
     * @dev If the number of seconds elapsed is greater than or equal to the EMA period, the EMA is updated to the last
     * funding value
     * @param secondsElapsed The number of seconds elapsed since the last protocol action
     * @return The new EMA value
     */
    function _updateEMA(Storage storage s, uint128 secondsElapsed) public returns (int256) {
        return s._EMA = calcEMA(s._lastFunding, secondsElapsed, s._EMAPeriod, s._EMA);
    }

    /**
     * @notice Variant of _adjustPrice when a fixed precision representation of the liquidation multiplier is known
     * @param unadjustedPrice The unadjusted price for the tick
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _adjustPrice(Storage storage s, uint256 unadjustedPrice, uint256 liqMultiplier)
        public
        view
        returns (uint128 price_)
    {
        // price = unadjustedPrice * M
        price_ = FixedPointMathLib.fullMulDiv(unadjustedPrice, liqMultiplier, 10 ** s.LIQUIDATION_MULTIPLIER_DECIMALS)
            .toUint128();
    }

    function funding(Storage storage s, uint128 timestamp) external view returns (int256 fund_, int256 oldLongExpo_) {
        (fund_, oldLongExpo_) = _funding(s, timestamp, s._EMA);
    }

    /**
     * @notice Calculate the funding rate and the old long exposure
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fund_ The funding rate
     * @return oldLongExpo_ The old long exposure
     */
    function _funding(Storage storage s, uint128 timestamp, int256 ema)
        public
        view
        returns (int256 fund_, int256 oldLongExpo_)
    {
        oldLongExpo_ = s._totalExpo.toInt256().safeSub(s._balanceLong.toInt256());

        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
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
}
