// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IBaseRebalancer } from "../../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Accumulator, HugeUint } from "../../libraries/Accumulator.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolLongLibrary {
    using Accumulator for HugeUint.Uint512;
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeTransferLib for address;
    using SignedMath for int256;

    /**
     * @dev Structure to hold the temporary data during liquidations.
     * @param tempLongBalance The updated long balance not saved into storage yet.
     * @param tempVaultBalance The updated vault balance not saved into storage yet.
     * @param currentTick The current tick (corresponding to the current asset price).
     * @param iTick Tick iterator index.
     * @param totalExpoToRemove The total exposure to remove due to liquidations.
     * @param accumulatorValueToRemove The value to remove from the liquidation multiplier accumulator due to
     * liquidations.
     * @param longTradingExpo The long trading exposure.
     * @param currentPrice The current price of the asset.
     * @param accumulator The liquidation multiplier accumulator before liquidations.
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate).
     */
    struct LiquidationData {
        int256 tempLongBalance;
        int256 tempVaultBalance;
        int24 currentTick;
        int24 iTick;
        uint256 totalExpoToRemove;
        uint256 accumulatorValueToRemove;
        uint256 longTradingExpo;
        uint256 currentPrice;
        HugeUint.Uint512 accumulator;
        bool isLiquidationPending;
    }

    /**
     * @dev Data structure for the `_applyPnlAndFundingAndLiquidate` function.
     * @param tempLongBalance The updated long balance not saved into storage yet.
     * @param tempVaultBalance The updated vault balance not saved into storage yet.
     * @param lastPrice The last price used to update the protocol.
     * @param rebased A boolean indicating if the USDN token was rebased.
     * @param callbackResult The result of the USDN rebase callback.
     * @param rebalancerAction The action performed by the `_triggerRebalancer` function.
     */
    struct ApplyPnlAndFundingAndLiquidateData {
        int256 tempLongBalance;
        int256 tempVaultBalance;
        uint128 lastPrice;
        bool rebased;
        bytes callbackResult;
        Types.RebalancerAction rebalancerAction;
    }

    /**
     * @dev Data structure for the `_triggerRebalancer` function.
     * @param positionAmount The amount of assets in the rebalancer's position.
     * @param rebalancerMaxLeverage The maximum leverage of the rebalancer.
     * @param rebalancerPosId The ID of the rebalancer's position.
     * @param positionValue The value of the rebalancer's position.
     */
    struct TriggerRebalancerData {
        uint128 positionAmount;
        uint256 rebalancerMaxLeverage;
        Types.PositionId rebalancerPosId;
        uint128 positionValue;
    }

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolLong.getPositionValue}.
    function getPositionValue(Types.PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        (Types.Position memory pos, uint24 liquidationPenalty) = ActionsUtils.getLongPosition(posId);
        uint256 longTradingExpo = Core.longTradingExpoWithFunding(price, timestamp);
        uint128 liqPrice = Utils._getEffectivePriceForTick(
            Utils._calcTickWithoutPenalty(posId.tick, liquidationPenalty),
            price,
            longTradingExpo,
            s._liqMultiplierAccumulator
        );
        value_ = Utils._positionValue(pos.totalExpo, price, liqPrice);
    }

    /// @notice See {IUsdnProtocolLong.getEffectiveTickForPrice(uint128)}.
    function getEffectiveTickForPrice(uint128 price) external view returns (int24 tick_) {
        Types.Storage storage s = Utils._getMainStorage();

        tick_ = getEffectiveTickForPrice(
            price, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator, s._tickSpacing
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolLong.minTick}.
    function minTick() public view returns (int24 tick_) {
        Types.Storage storage s = Utils._getMainStorage();

        tick_ = TickMath.minUsableTick(s._tickSpacing);
    }

    /// @notice See {IUsdnProtocolLong.getTickLiquidationPenalty}.
    function getTickLiquidationPenalty(int24 tick) public view returns (uint24 liquidationPenalty_) {
        (bytes32 tickHash,) = Utils._tickHash(tick);
        liquidationPenalty_ = _getTickLiquidationPenalty(tickHash);
    }

    /// @notice See {IUsdnProtocolLong.getEffectiveTickForPrice(uint128,uint256,uint256,HugeUint.Uint512,int24)}.
    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) public pure returns (int24 tick_) {
        tick_ = _getEffectiveTickForPriceNoRounding(price, assetPrice, longTradingExpo, accumulator);

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        tick_ = _roundTickDown(tick_, tickSpacing);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Applies PnL, funding, and liquidates positions if necessary.
     * @dev If there were any liquidations, it sends the rewards to the `msg.sender`.
     * @param neutralPrice The neutral price for the asset.
     * @param timestamp The timestamp at which the operation is performed.
     * @param iterations The number of iterations for the liquidation process.
     * @param action The type of action that is being performed by the user.
     * @param priceData The data given to the oracle middleware corresponding to `neutralPrice`.
     * @return liquidatedTicks_ Information about the liquidated ticks.
     * @return isLiquidationPending_ If there are remaining ticks that can be liquidated.
     */
    function _applyPnlAndFundingAndLiquidate(
        uint256 neutralPrice,
        uint256 timestamp,
        uint16 iterations,
        Types.ProtocolAction action,
        bytes calldata priceData
    ) public returns (Types.LiqTickInfo[] memory liquidatedTicks_, bool isLiquidationPending_) {
        Types.Storage storage s = Utils._getMainStorage();

        ApplyPnlAndFundingAndLiquidateData memory data;
        {
            Types.ApplyPnlAndFundingData memory temporaryData =
                Core._applyPnlAndFunding(neutralPrice.toUint128(), timestamp.toUint128());
            assembly {
                mcopy(data, temporaryData, 128)
            }
        }

        // liquidate with `_lastPrice` if there are pending liquidations, up to `iterations` ticks
        Types.LiquidationsEffects memory liquidationEffects =
            _liquidatePositions(data.lastPrice, iterations, data.tempLongBalance, data.tempVaultBalance);

        isLiquidationPending_ = liquidationEffects.isLiquidationPending;
        if (!isLiquidationPending_ && liquidationEffects.liquidatedTicks.length > 0) {
            if (s._closeExpoImbalanceLimitBps > 0) {
                (liquidationEffects.newLongBalance, liquidationEffects.newVaultBalance, data.rebalancerAction) =
                _triggerRebalancer(
                    data.lastPrice,
                    liquidationEffects.newLongBalance,
                    liquidationEffects.newVaultBalance,
                    liquidationEffects.remainingCollateral
                );
            }
        }

        s._balanceLong = liquidationEffects.newLongBalance;
        s._balanceVault = liquidationEffects.newVaultBalance;

        (data.rebased, data.callbackResult) = _usdnRebase(data.lastPrice);

        if (liquidationEffects.liquidatedTicks.length > 0) {
            _sendRewardsToLiquidator(
                liquidationEffects.liquidatedTicks,
                data.lastPrice,
                data.rebased,
                data.rebalancerAction,
                action,
                data.callbackResult,
                priceData
            );
        }

        liquidatedTicks_ = liquidationEffects.liquidatedTicks;
    }

    /**
     * @notice Prepares the data for the `initiateOpenPosition` function.
     * @param params The parameters for the `_prepareInitiateOpenPositionData` function.
     * @return data_ The transient data for the open position action.
     */
    function _prepareInitiateOpenPositionData(Types.PrepareInitiateOpenPositionParams calldata params)
        public
        returns (Types.InitiateOpenPositionData memory data_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.InitiateOpenPosition,
            block.timestamp,
            Utils._calcActionId(params.validator, uint128(block.timestamp)),
            params.currentPriceData
        );

        uint128 neutralPrice = currentPrice.neutralPrice.toUint128();
        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            Types.ProtocolAction.InitiateOpenPosition,
            params.currentPriceData
        );
        // early return in case there are still pending liquidations
        if (data_.isLiquidationPending) {
            return data_;
        }

        uint128 lastPrice = s._lastPrice;
        // add position fee
        data_.adjustedPrice = (lastPrice + uint256(lastPrice) * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();

        // check slippage
        if (data_.adjustedPrice > params.userMaxPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolSlippageMaxPriceExceeded();
        }

        // gas savings, we only load the data once and use it for all conversions below
        Types.TickPriceConversionData memory conversionData = Types.TickPriceConversionData({
            // we need to take into account the funding for the trading exposure between
            // the last price timestamp and now
            tradingExpo: Core.longTradingExpoWithFunding(lastPrice, uint128(block.timestamp)),
            accumulator: s._liqMultiplierAccumulator,
            tickSpacing: s._tickSpacing
        });

        // we calculate the closest valid tick down for the desired liq price with liquidation penalty
        data_.posId.tick = getEffectiveTickForPrice(
            params.desiredLiqPrice,
            lastPrice,
            conversionData.tradingExpo,
            conversionData.accumulator,
            conversionData.tickSpacing
        );
        data_.liquidationPenalty = getTickLiquidationPenalty(data_.posId.tick);

        // calculate effective liquidation price
        uint128 liqPrice = Utils._getEffectivePriceForTick(
            data_.posId.tick, lastPrice, conversionData.tradingExpo, conversionData.accumulator
        );

        // liquidation price must be at least x% below the current price
        _checkSafetyMargin(lastPrice, liqPrice);

        // remove liquidation penalty for leverage and total exposure calculations
        uint128 liqPriceWithoutPenalty = Utils._getEffectivePriceForTick(
            Utils._calcTickWithoutPenalty(data_.posId.tick, data_.liquidationPenalty),
            lastPrice,
            conversionData.tradingExpo,
            conversionData.accumulator
        );
        _checkOpenPositionLeverage(data_.adjustedPrice, liqPriceWithoutPenalty, params.userMaxLeverage);

        data_.positionTotalExpo =
            Utils._calcPositionTotalExpo(params.amount, data_.adjustedPrice, liqPriceWithoutPenalty);
        // the current price is known to be above the liquidation price because we checked the safety margin
        data_.positionValue = Utils._positionValueOptimized(data_.positionTotalExpo, lastPrice, liqPriceWithoutPenalty);
        _checkImbalanceLimitOpen(data_.positionTotalExpo, params.amount, data_.positionValue);

        data_.liqMultiplier =
            Utils._calcFixedPrecisionMultiplier(lastPrice, conversionData.tradingExpo, conversionData.accumulator);
    }

    /**
     * @notice Removes `amountToRemove` from position `pos` then updates the tick data and the position.
     * @dev This method does not update the long balance.
     * If the amount to remove is greater than or equal to the position's total amount, the position is deleted instead.
     * @param tick The tick the position is in.
     * @param index Index of the position in the tick array.
     * @param pos The position to remove the amount from.
     * @param amountToRemove The amount to remove from the position.
     * @param totalExpoToRemove The total exposure to remove from the position.
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator.
     */
    function _removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Types.Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) public returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        Types.Storage storage s = Utils._getMainStorage();

        (bytes32 tickHash,) = Utils._tickHash(tick);
        Types.TickData storage tickData = s._tickData[tickHash];
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(Utils._calcTickWithoutPenalty(tick, tickData.liquidationPenalty));
        if (amountToRemove < pos.amount) {
            Types.Position storage position = s._longPositions[tickHash][index];
            position.totalExpo = pos.totalExpo - totalExpoToRemove;

            unchecked {
                position.amount = pos.amount - amountToRemove;
            }
        } else {
            totalExpoToRemove = pos.totalExpo;
            tickData.totalPos -= 1;
            --s._totalLongPositions;

            // remove from tick array (set to zero to avoid shifting indices)
            delete s._longPositions[tickHash][index];
            if (tickData.totalPos == 0) {
                // we removed the last position in the tick
                s._tickBitmap.unset(Utils._calcBitmapIndexFromTick(tick));
                // reset tick penalty
                tickData.liquidationPenalty = 0;
            }
        }

        s._totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
        liqMultiplierAccumulator_ =
            s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * totalExpoToRemove));
        s._liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /**
     * @notice Computes the tick number with penalty and liquidation price without penalty
     * from the desired liquidation price.
     * @dev This function first calculates a tick for the desired liquidation price (no rounding), then adds the penalty
     * to the tick and rounds down to the nearest tick spacing. Then it subtracts the penalty from the final tick and
     * calculates the corresponding liquidation price.
     * @param desiredLiqPriceWithoutPenalty The desired liquidation price without penalty.
     * @param liquidationPenalty The liquidation penalty.
     * @return tickWithPenalty_ The tick number including the liquidation penalty.
     * @return liqPriceWithoutPenalty_ The liquidation price without penalty.
     */
    function _getTickFromDesiredLiqPrice(uint128 desiredLiqPriceWithoutPenalty, uint24 liquidationPenalty)
        public
        view
        returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        return _getTickFromDesiredLiqPrice(
            desiredLiqPriceWithoutPenalty,
            s._lastPrice,
            s._totalExpo - s._balanceLong,
            s._liqMultiplierAccumulator,
            s._tickSpacing,
            liquidationPenalty
        );
    }

    /**
     * @notice Computes the tick number with penalty and liquidation price without penalty
     * from the desired liquidation price and protocol state.
     * @dev This function first calculates a tick for the desired liquidation price (no rounding), then adds the penalty
     * to the tick and rounds down to the nearest tick spacing. Then it subtracts the penalty from the final tick and
     * calculates the corresponding liquidation price.
     * @param desiredLiqPriceWithoutPenalty The desired liquidation price without penalty.
     * @param assetPrice The current price of the asset.
     * @param longTradingExpo The trading exposure of the long side (total exposure - balance long).
     * @param accumulator The liquidation multiplier accumulator.
     * @param tickSpacing The tick spacing.
     * @param liquidationPenalty The liquidation penalty.
     * @return tickWithPenalty_ The tick number including the liquidation penalty.
     * @return liqPriceWithoutPenalty_ The liquidation price without penalty.
     */
    function _getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) public pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
        // get corresponding tick (not necessarily a multiple of tickSpacing)
        int24 tempTickWithoutPenalty =
            _getEffectiveTickForPriceNoRounding(desiredLiqPriceWithoutPenalty, assetPrice, longTradingExpo, accumulator);
        // add the penalty to the tick and round down to the nearest multiple of tickSpacing
        tickWithPenalty_ = tempTickWithoutPenalty + int24(liquidationPenalty);
        tickWithPenalty_ = _roundTickDownWithPenalty(tickWithPenalty_, tickSpacing, liquidationPenalty);
        liqPriceWithoutPenalty_ = Utils._getEffectivePriceForTick(
            Utils._calcTickWithoutPenalty(tickWithPenalty_, liquidationPenalty),
            assetPrice,
            longTradingExpo,
            accumulator
        );
    }

    /**
     * @notice Computes the tick number with penalty and liquidation price without penalty
     * from the desired liquidation price and a fixed precision version of the liquidation multiplier accumulator.
     * @dev This function first calculates a tick for the desired liquidation price (no rounding), then adds the penalty
     * to the tick and rounds down to the nearest tick spacing. Then it subtracts the penalty from the final tick and
     * calculates the corresponding liquidation price.
     * @param desiredLiqPriceWithoutPenalty The desired liquidation price without penalty.
     * @param liqMultiplier The liquidation price multiplier (with `LIQUIDATION_MULTIPLIER_DECIMALS` decimals).
     * @param tickSpacing The tick spacing.
     * @param liquidationPenalty The liquidation penalty.
     * @return tickWithPenalty_ The tick number including the liquidation penalty.
     * @return liqPriceWithoutPenalty_ The liquidation price without penalty.
     */
    function _getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 liqMultiplier,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) public pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
        // get corresponding tick (not necessarily a multiple of tickSpacing)
        int24 tempTickWithoutPenalty = _getEffectiveTickForPriceNoRounding(desiredLiqPriceWithoutPenalty, liqMultiplier);
        // add the penalty to the tick and round down to the nearest multiple of tickSpacing
        tickWithPenalty_ = tempTickWithoutPenalty + int24(liquidationPenalty);
        tickWithPenalty_ = _roundTickDownWithPenalty(tickWithPenalty_, tickSpacing, liquidationPenalty);
        liqPriceWithoutPenalty_ = Utils._getEffectivePriceForTick(
            Utils._calcTickWithoutPenalty(tickWithPenalty_, liquidationPenalty), liqMultiplier
        );
    }

    /**
     * @notice Finds the highest tick that contains at least one position.
     * @dev If there are no ticks with a position left, returns {minTick}.
     * @param searchStart The tick to start searching from.
     * @return tick_ The highest tick at or below `searchStart`.
     */
    function _findHighestPopulatedTick(int24 searchStart) public view returns (int24 tick_) {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 index = s._tickBitmap.findLastSet(Utils._calcBitmapIndexFromTick(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick();
        } else {
            tick_ = _calcTickFromBitmapIndex(index);
        }
    }

    /**
     * @notice Checks if a USDN rebase is required and adjust the divisor if needed.
     * @dev Only call this function after `_applyPnlAndFunding` has been called to update the balances.
     * @param assetPrice The current price of the underlying asset.
     * @return rebased_ Whether a rebase was performed.
     * @return callbackResult_ The rebase callback result, if any.
     */
    function _usdnRebase(uint128 assetPrice) internal returns (bool rebased_, bytes memory callbackResult_) {
        Types.Storage storage s = Utils._getMainStorage();

        IUsdn usdn = s._usdn;
        uint256 divisor = usdn.divisor();
        if (divisor <= s._usdnMinDivisor) {
            // no need to rebase, the USDN divisor cannot go lower
            return (false, callbackResult_);
        }

        uint256 balanceVault = s._balanceVault;
        uint8 assetDecimals = s._assetDecimals;
        uint256 usdnTotalSupply = usdn.totalSupply();
        uint256 uPrice = Vault._calcUsdnPrice(balanceVault, assetPrice, usdnTotalSupply, assetDecimals);
        if (uPrice <= s._usdnRebaseThreshold) {
            return (false, callbackResult_);
        }

        uint256 targetTotalSupply = _calcRebaseTotalSupply(balanceVault, assetPrice, s._targetUsdnPrice, assetDecimals);
        uint256 newDivisor = FixedPointMathLib.fullMulDiv(usdnTotalSupply, divisor, targetTotalSupply);

        // since the USDN token can call a handler after the rebase, we want to make sure we do not block the user
        // action in case the rebase fails
        try usdn.rebase(newDivisor) returns (bool rebased, uint256, bytes memory callbackResult) {
            rebased_ = rebased;
            callbackResult_ = callbackResult;
        } catch { }
    }

    /**
     * @notice Sends rewards to the liquidator.
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain.
     * @param liquidatedTicks Information about the liquidated ticks.
     * @param currentPrice The current price of the asset.
     * @param rebased Whether a USDN rebase was performed.
     * @param rebalancerAction The rebalancer action that was performed.
     * @param action The protocol action that triggered liquidations.
     * @param rebaseCallbackResult The rebase callback result, if any.
     * @param priceData The data given to the oracle middleware to get a price.
     */
    function _sendRewardsToLiquidator(
        Types.LiqTickInfo[] memory liquidatedTicks,
        uint256 currentPrice,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        Types.ProtocolAction action,
        bytes memory rebaseCallbackResult,
        bytes memory priceData
    ) internal {
        Types.Storage storage s = Utils._getMainStorage();

        // get how much we should give to the liquidator as rewards
        uint256 liquidationRewards = s._liquidationRewardsManager.getLiquidationRewards(
            liquidatedTicks, currentPrice, rebased, rebalancerAction, action, rebaseCallbackResult, priceData
        );

        // avoid underflows in the situation of extreme bad debt
        if (s._balanceVault < liquidationRewards) {
            liquidationRewards = s._balanceVault;
        }

        // update the vault's balance
        unchecked {
            s._balanceVault -= liquidationRewards;
        }

        // transfer rewards (assets) to the liquidator
        address(s._asset).safeTransfer(msg.sender, liquidationRewards);

        emit IUsdnProtocolEvents.LiquidatorRewarded(msg.sender, liquidationRewards);
    }

    /**
     * @notice Triggers the rebalancer if the imbalance on the long side is too high.
     * It will close the rebalancer's position (if there is one) and open a new one with the pending assets, the value
     * of the previous position and the liquidation bonus (if available) with a leverage that would fill enough trading
     * exposure to reach the desired imbalance, up to the max leverages.
     * @dev Only call this function after liquidations are performed to have a non-zero `remainingCollateral` value.
     * Will return the provided long and vault balances if no rebalancer is set or if the imbalance is not high enough.
     * If `remainingCollateral` is negative, the rebalancer bonus will be 0.
     * @param lastPrice The last price used to update the protocol.
     * @param longBalance The balance of the long side.
     * @param vaultBalance The balance of the vault side.
     * @param remainingCollateral The collateral remaining after the liquidations.
     * @return longBalance_ The updated long balance not saved into storage yet.
     * @return vaultBalance_ The updated vault balance not saved into storage yet.
     * @return action_ The action performed by this function.
     */
    function _triggerRebalancer(
        uint128 lastPrice,
        uint256 longBalance,
        uint256 vaultBalance,
        int256 remainingCollateral
    ) internal returns (uint256 longBalance_, uint256 vaultBalance_, Types.RebalancerAction action_) {
        Types.Storage storage s = Utils._getMainStorage();

        longBalance_ = longBalance;
        vaultBalance_ = vaultBalance;
        IBaseRebalancer rebalancer = s._rebalancer;

        if (address(rebalancer) == address(0)) {
            return (longBalance_, vaultBalance_, Types.RebalancerAction.None);
        }

        Types.CachedProtocolState memory cache;
        {
            int256 tempVaultBalance = vaultBalance.toInt256() + s._pendingBalanceVault;
            // clamp the vault balance to 0 to avoid underflows
            if (tempVaultBalance < 0) {
                tempVaultBalance = 0;
            }

            cache = Types.CachedProtocolState({
                totalExpo: s._totalExpo,
                longBalance: longBalance,
                // cast is safe as value cannot be negative
                vaultBalance: uint256(tempVaultBalance),
                tradingExpo: 0,
                liqMultiplierAccumulator: s._liqMultiplierAccumulator
            });
        }

        if (cache.totalExpo < cache.longBalance) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo();
        }

        cache.tradingExpo = cache.totalExpo - cache.longBalance;

        // calculate the bonus now and update the cache to make sure removing it from the vault doesn't push the
        // imbalance above the threshold
        uint128 bonus;
        if (remainingCollateral > 0) {
            bonus = (uint256(remainingCollateral) * s._rebalancerBonusBps / Constants.BPS_DIVISOR).toUint128();
            if (bonus > cache.vaultBalance) {
                bonus = cache.vaultBalance.toUint128();
            }

            cache.vaultBalance -= bonus;
        }

        {
            int256 currentImbalance = Utils._calcImbalanceCloseBps(
                cache.vaultBalance.toInt256(), cache.longBalance.toInt256(), cache.totalExpo
            );

            // if the imbalance is lower than the threshold, return
            if (currentImbalance <= s._closeExpoImbalanceLimitBps) {
                return (longBalance_, vaultBalance_, Types.RebalancerAction.NoImbalance);
            }
        }

        TriggerRebalancerData memory data;
        // the default value of `positionAmount` is the amount of pendingAssets in the rebalancer
        (data.positionAmount, data.rebalancerMaxLeverage, data.rebalancerPosId) = rebalancer.getCurrentStateData();

        // close the rebalancer position and get its value to open the next one
        if (data.rebalancerPosId.tick != Constants.NO_POSITION_TICK) {
            // cached values will be updated during this call
            int256 realPositionValue = _flashClosePosition(data.rebalancerPosId, lastPrice, cache);

            // if the position value is less than 0, it should have been liquidated but wasn't
            // interrupt the whole rebalancer process because there are pending liquidations
            if (realPositionValue < 0) {
                return (longBalance_, vaultBalance_, Types.RebalancerAction.PendingLiquidation);
            }

            // cast is safe as realPositionValue cannot be lower than 0
            data.positionValue = uint256(realPositionValue).toUint128();
            data.positionAmount += data.positionValue;
            longBalance_ -= data.positionValue;
        } else if (data.positionAmount == 0) {
            // avoid to update an empty rebalancer
            return (longBalance_, vaultBalance_, Types.RebalancerAction.NoCloseNoOpen);
        }

        // if the amount in the position we wanted to open is below a fraction of the _minLongPosition setting,
        // we are dealing with dust. So we should stop the process and gift the remaining value to the vault
        if (data.positionAmount <= s._minLongPosition / 10_000) {
            // make the rebalancer believe that the previous position was liquidated,
            // and inform it that no new position was open so it can start anew
            rebalancer.updatePosition(Types.PositionId(Constants.NO_POSITION_TICK, 0, 0), 0);
            vaultBalance_ += data.positionValue;
            return (longBalance_, vaultBalance_, Types.RebalancerAction.Closed);
        }

        // transfer the pending assets from the rebalancer to this contract
        // slither-disable-next-line arbitrary-send-erc20
        address(s._asset).safeTransferFrom(address(rebalancer), address(this), data.positionAmount - data.positionValue);

        // add the bonus to the new rebalancer position and remove it from the vault
        if (bonus > 0) {
            // those operations will not underflow because the bonus is capped by `remainingCollateral`
            // which was given to the vault before the trigger, so vaultBalance is always greater than or equal to bonus
            vaultBalance_ -= bonus;
            data.positionAmount += bonus;
        }

        Types.RebalancerPositionData memory posData =
            _calcRebalancerPositionTick(lastPrice, data.positionAmount, data.rebalancerMaxLeverage, cache);

        // open a new position for the rebalancer
        Types.PositionId memory posId = _flashOpenPosition(
            address(rebalancer),
            lastPrice,
            posData.tick,
            posData.totalExpo,
            posData.liquidationPenalty,
            data.positionAmount
        );

        longBalance_ += data.positionAmount;

        // call the rebalancer to update the public bookkeeping
        rebalancer.updatePosition(posId, data.positionValue);

        if (data.positionValue > 0) {
            action_ = Types.RebalancerAction.ClosedOpened;
        } else {
            action_ = Types.RebalancerAction.Opened;
        }
    }

    /**
     * @notice Immediately opens a position with the given price.
     * @dev Should only be used to open the rebalancer's position.
     * @param user The address of the rebalancer.
     * @param lastPrice The last price used to update the protocol.
     * @param tick The tick the position should be opened in.
     * @param posTotalExpo The total exposure of the position.
     * @param liquidationPenalty The liquidation penalty of the tick.
     * @param amount The amount of collateral in the position.
     * @return posId_ The ID of the position that was created.
     */
    function _flashOpenPosition(
        address user,
        uint128 lastPrice,
        int24 tick,
        uint128 posTotalExpo,
        uint24 liquidationPenalty,
        uint128 amount
    ) internal returns (Types.PositionId memory posId_) {
        posId_.tick = tick;
        Types.Position memory long = Types.Position({
            validated: true,
            user: user,
            amount: amount,
            totalExpo: posTotalExpo,
            timestamp: uint40(block.timestamp)
        });

        // save the position on the provided tick
        (posId_.tickVersion, posId_.index,) = Core._saveNewPosition(posId_.tick, long, liquidationPenalty);

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        emit IUsdnProtocolEvents.InitiatedOpenPosition(
            user, user, uint40(block.timestamp), posTotalExpo, long.amount, lastPrice, posId_
        );
        emit IUsdnProtocolEvents.ValidatedOpenPosition(user, user, posTotalExpo, lastPrice, posId_);
    }

    /**
     * @notice Immediately closes a position with the given price.
     * @dev Should only be used to close the rebalancer's position.
     * @param posId The ID of the position to close.
     * @param lastPrice The last price used to update the protocol.
     * @param cache The cached state of the protocol, will be updated during this call.
     * @return positionValue_ The value of the closed position.
     */
    function _flashClosePosition(
        Types.PositionId memory posId,
        uint128 lastPrice,
        Types.CachedProtocolState memory cache
    ) internal returns (int256 positionValue_) {
        Types.Storage storage s = Utils._getMainStorage();

        (bytes32 tickHash, uint256 version) = Utils._tickHash(posId.tick);
        // if the tick version is outdated, the position was liquidated and its value is 0
        if (posId.tickVersion != version) {
            return positionValue_;
        }

        uint24 liquidationPenalty = s._tickData[tickHash].liquidationPenalty;
        Types.Position memory pos = s._longPositions[tickHash][posId.index];

        positionValue_ = Utils._positionValue(
            pos.totalExpo,
            lastPrice,
            Utils._getEffectivePriceForTick(
                Utils._calcTickWithoutPenalty(posId.tick, liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            )
        );

        // if positionValue is lower than 0, return
        if (positionValue_ < 0) {
            return positionValue_;
        }

        // fully close the position and update the cache
        cache.liqMultiplierAccumulator =
            _removeAmountFromPosition(posId.tick, posId.index, pos, pos.amount, pos.totalExpo);

        // update the cache
        cache.totalExpo -= pos.totalExpo;
        // cast is safe as positionValue cannot be lower than 0
        if (cache.longBalance >= uint256(positionValue_)) {
            cache.longBalance -= uint256(positionValue_);
        } else {
            // case is safe as the long balance is below the position value which is an int256
            positionValue_ = int256(cache.longBalance);
            cache.longBalance = 0;
        }
        cache.tradingExpo = cache.totalExpo - cache.longBalance;

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        emit IUsdnProtocolEvents.InitiatedClosePosition(pos.user, pos.user, pos.user, posId, pos.amount, pos.amount, 0);
        emit IUsdnProtocolEvents.ValidatedClosePosition(
            pos.user, pos.user, posId, uint256(positionValue_), positionValue_ - Utils._toInt256(pos.amount)
        );
    }

    /**
     * @notice Liquidates positions that have a liquidation price lower than the current price.
     * @param currentPrice The current price of the asset.
     * @param iteration The maximum number of ticks to liquidate (minimum is 1).
     * @param tempLongBalance The temporary long balance as calculated when applying the PnL and funding.
     * @param tempVaultBalance The temporary vault balance as calculated when applying the PnL and funding.
     * @return effects_ The effects of the liquidations on the protocol.
     */
    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) internal returns (Types.LiquidationsEffects memory effects_) {
        Types.Storage storage s = Utils._getMainStorage();

        LiquidationData memory data;
        data.tempLongBalance = tempLongBalance;
        data.tempVaultBalance = tempVaultBalance;
        // cast is safe as tempLongBalance cannot exceed s._totalExpo
        data.longTradingExpo = uint256(s._totalExpo.toInt256() - tempLongBalance);
        data.currentPrice = currentPrice;
        data.accumulator = s._liqMultiplierAccumulator;

        // max iteration limit
        if (iteration > Constants.MAX_LIQUIDATION_ITERATION) {
            iteration = Constants.MAX_LIQUIDATION_ITERATION;
        }

        effects_.liquidatedTicks = new Types.LiqTickInfo[](iteration);

        // For small prices (< ~1.025 gwei), the next tick can sometimes
        // give a price that is exactly equal to the input. For this to be somewhat of an issue,
        // we would need the tick spacing to be 1 and the price to fall to an extremely low price,
        // which is unlikely, but should be considered for tokens with extremely high total supply
        uint256 unadjustedPrice =
            _unadjustPrice(data.currentPrice, data.currentPrice, data.longTradingExpo, data.accumulator);
        data.currentTick = TickMath.getTickAtPrice(unadjustedPrice);
        data.iTick = s._highestPopulatedTick;
        uint256 i;
        do {
            uint256 index = s._tickBitmap.findLastSet(Utils._calcBitmapIndexFromTick(data.iTick));
            if (index == LibBitmap.NOT_FOUND) {
                // no populated ticks left
                break;
            }

            data.iTick = _calcTickFromBitmapIndex(index);
            if (data.iTick < data.currentTick) {
                // all ticks that can be liquidated have been processed
                break;
            }

            // we have found a non-empty tick that needs to be liquidated
            (bytes32 tickHash,) = Utils._tickHash(data.iTick);

            Types.TickData memory tickData = s._tickData[tickHash];
            // update transient data
            data.totalExpoToRemove += tickData.totalExpo;
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(Utils._calcTickWithoutPenalty(data.iTick, tickData.liquidationPenalty));
            data.accumulatorValueToRemove += unadjustedTickPrice * tickData.totalExpo;
            // update return values
            effects_.liquidatedTicks[i] = Types.LiqTickInfo({
                totalPositions: tickData.totalPos,
                totalExpo: tickData.totalExpo,
                remainingCollateral: _tickValue(
                    data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator, tickData
                ),
                tickPrice: Utils._getEffectivePriceForTick(
                    data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator
                ),
                priceWithoutPenalty: Utils._getEffectivePriceForTick(
                    Utils._calcTickWithoutPenalty(data.iTick, tickData.liquidationPenalty),
                    data.currentPrice,
                    data.longTradingExpo,
                    data.accumulator
                )
            });
            effects_.liquidatedPositions += tickData.totalPos;
            effects_.remainingCollateral += effects_.liquidatedTicks[i].remainingCollateral;

            // reset tick by incrementing the tick version
            ++s._tickVersion[data.iTick];
            // update bitmap to reflect that the tick is empty
            s._tickBitmap.unset(index);

            emit IUsdnProtocolEvents.LiquidatedTick(
                data.iTick,
                s._tickVersion[data.iTick] - 1,
                data.currentPrice,
                effects_.liquidatedTicks[i].tickPrice,
                effects_.liquidatedTicks[i].remainingCollateral
            );

            unchecked {
                i++;
            }
        } while (i < iteration);
        // shrink array
        Types.LiqTickInfo[] memory liqTicks = effects_.liquidatedTicks;
        assembly ("memory-safe") {
            mstore(liqTicks, i)
        }

        _updateStateAfterLiquidation(data, effects_); // mutates `data`
        effects_.isLiquidationPending = data.isLiquidationPending;
        (effects_.newLongBalance, effects_.newVaultBalance) =
            _handleNegativeBalances(data.tempLongBalance, data.tempVaultBalance);
    }

    /**
     * @notice Updates the state of the contract according to the liquidation effects.
     * @param data The liquidation data, which gets mutated by the function.
     * @param effects The effects of the liquidations.
     */
    function _updateStateAfterLiquidation(LiquidationData memory data, Types.LiquidationsEffects memory effects)
        internal
    {
        Types.Storage storage s = Utils._getMainStorage();

        // update the state
        s._totalLongPositions -= effects.liquidatedPositions;
        s._totalExpo -= data.totalExpoToRemove;
        s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.sub(HugeUint.wrap(data.accumulatorValueToRemove));

        // keep track of the highest populated tick
        if (effects.liquidatedPositions != 0) {
            int24 highestPopulatedTick;
            if (data.iTick < data.currentTick) {
                // all ticks above the current tick were liquidated
                highestPopulatedTick = _findHighestPopulatedTick(data.currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                highestPopulatedTick = _findHighestPopulatedTick(data.iTick);
                data.isLiquidationPending = data.currentTick <= highestPopulatedTick;
            }

            s._highestPopulatedTick = highestPopulatedTick;
            emit IUsdnProtocolEvents.HighestPopulatedTickUpdated(highestPopulatedTick);
        }

        // transfer remaining collateral to vault or pay bad debt
        data.tempLongBalance -= effects.remainingCollateral;
        data.tempVaultBalance += effects.remainingCollateral;
    }

    /**
     * @notice Checks if the position's leverage is in the authorized range of values.
     * @param adjustedPrice The adjusted price of the asset.
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty.
     * @param userMaxLeverage The maximum leverage allowed by the user for the newly created position.
     */
    function _checkOpenPositionLeverage(uint128 adjustedPrice, uint128 liqPriceWithoutPenalty, uint256 userMaxLeverage)
        internal
        view
    {
        Types.Storage storage s = Utils._getMainStorage();

        // calculate position leverage
        // reverts if liquidationPrice >= entryPrice
        uint256 leverage = Utils._getLeverage(adjustedPrice, liqPriceWithoutPenalty);

        if (leverage < s._minLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolLeverageTooLow();
        }

        uint256 protocolMaxLeverage = s._maxLeverage;
        if (userMaxLeverage > protocolMaxLeverage) {
            userMaxLeverage = protocolMaxLeverage;
        }

        if (leverage > userMaxLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolLeverageTooHigh();
        }
    }

    /**
     * @notice Checks and reverts if the position's trading exposure exceeds the imbalance limits.
     * @param openTotalExpoValue The total exposure of the position to open.
     * @param collateralAmount The amount of collateral of the position.
     * @param collateralAmountAfterFees The amount of collateral of the position after fees.
     */
    function _checkImbalanceLimitOpen(
        uint256 openTotalExpoValue,
        uint256 collateralAmount,
        uint256 collateralAmountAfterFees
    ) internal view {
        Types.Storage storage s = Utils._getMainStorage();

        int256 openExpoImbalanceLimitBps = s._openExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (openExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault).safeAdd(
            (collateralAmount - collateralAmountAfterFees).toInt256()
        );

        int256 imbalanceBps = _calcImbalanceOpenBps(
            currentVaultExpo, (s._balanceLong + collateralAmountAfterFees).toInt256(), s._totalExpo + openTotalExpoValue
        );

        if (imbalanceBps > openExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Calculates the tick of the rebalancer position to open.
     * @dev The returned tick must give a leverage higher than or equal to the minimum leverage of the protocol
     * and lower than or equal to the rebalancer and USDN protocol leverages (lowest of the 2).
     * @param lastPrice The last price used to update the protocol.
     * @param positionAmount The amount of assets in the position.
     * @param rebalancerMaxLeverage The maximum leverage supported by the rebalancer.
     * @param cache The cached protocol state values.
     * @return posData_ The tick, total exposure and liquidation penalty for the rebalancer position.
     */
    function _calcRebalancerPositionTick(
        uint128 lastPrice,
        uint128 positionAmount,
        uint256 rebalancerMaxLeverage,
        Types.CachedProtocolState memory cache
    ) internal view returns (Types.RebalancerPositionData memory posData_) {
        Types.Storage storage s = Utils._getMainStorage();

        Types.CalcRebalancerPositionTickData memory data;

        data.protocolMaxLeverage = s._maxLeverage;
        if (rebalancerMaxLeverage > data.protocolMaxLeverage) {
            rebalancerMaxLeverage = data.protocolMaxLeverage;
        }

        data.longImbalanceTargetBps = s._longImbalanceTargetBps;
        // calculate the trading exposure missing to reach the imbalance target
        uint256 targetTradingExpo = (
            cache.vaultBalance * Constants.BPS_DIVISOR
                / (int256(Constants.BPS_DIVISOR) + data.longImbalanceTargetBps).toUint256()
        );

        // make sure that the rebalancer was not triggered without a sufficient imbalance
        // as we check the imbalance above, this should not happen
        if (cache.tradingExpo >= targetTradingExpo) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerTick();
        }

        uint256 tradingExpoToFill = targetTradingExpo - cache.tradingExpo;

        // check that the trading exposure filled by the position would not exceed the max leverage
        data.highestUsableTradingExpo =
            positionAmount * rebalancerMaxLeverage / 10 ** Constants.LEVERAGE_DECIMALS - positionAmount;
        if (data.highestUsableTradingExpo < tradingExpoToFill) {
            tradingExpoToFill = data.highestUsableTradingExpo;
        }

        data.currentLiqPenalty = s._liquidationPenalty;
        uint128 idealLiqPrice = _calcLiqPriceFromTradingExpo(lastPrice, positionAmount, tradingExpoToFill);

        (posData_.tick, data.liqPriceWithoutPenalty) = _getTickFromDesiredLiqPrice(
            idealLiqPrice,
            lastPrice,
            cache.tradingExpo,
            cache.liqMultiplierAccumulator,
            s._tickSpacing,
            data.currentLiqPenalty
        );

        posData_.liquidationPenalty = getTickLiquidationPenalty(posData_.tick);
        if (posData_.liquidationPenalty != data.currentLiqPenalty) {
            data.liqPriceWithoutPenalty = Utils._getEffectivePriceForTick(
                Utils._calcTickWithoutPenalty(posData_.tick, posData_.liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            );
        }
        posData_.totalExpo = Utils._calcPositionTotalExpo(positionAmount, lastPrice, data.liqPriceWithoutPenalty);

        // due to the rounding down, if the imbalance is still greater than the desired imbalance
        // and the position is not at the max leverage, add one tick
        if (
            data.highestUsableTradingExpo != tradingExpoToFill
                && Utils._calcImbalanceCloseBps(
                    cache.vaultBalance.toInt256(),
                    (cache.longBalance + positionAmount).toInt256(),
                    cache.totalExpo + posData_.totalExpo
                ) > data.longImbalanceTargetBps
        ) {
            posData_.tick += s._tickSpacing;
            posData_.liquidationPenalty = getTickLiquidationPenalty(posData_.tick);
            data.liqPriceWithoutPenalty = Utils._getEffectivePriceForTick(
                Utils._calcTickWithoutPenalty(posData_.tick, posData_.liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            );
            posData_.totalExpo = Utils._calcPositionTotalExpo(positionAmount, lastPrice, data.liqPriceWithoutPenalty);
        }
    }

    /**
     * @notice Checks and reverts if the leverage of a position exceeds the safety margin.
     * @param currentPrice The current price of the asset.
     * @param liquidationPrice The liquidation price of the position.
     */
    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        Types.Storage storage s = Utils._getMainStorage();

        uint128 maxLiquidationPrice =
            (currentPrice * (Constants.BPS_DIVISOR - s._safetyMarginBps) / Constants.BPS_DIVISOR).toUint128();
        if (liquidationPrice >= maxLiquidationPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    /**
     * @notice Retrieves the liquidation penalty assigned to the given `tickHash`.
     * @dev If there are no positions in it, returns the current setting from storage.
     * @param tickHash The tick hash (hashed tick number + version).
     * @return liquidationPenalty_ The liquidation penalty (in tick spacing units).
     */
    function _getTickLiquidationPenalty(bytes32 tickHash) internal view returns (uint24 liquidationPenalty_) {
        Types.Storage storage s = Utils._getMainStorage();

        Types.TickData storage tickData = s._tickData[tickHash];
        liquidationPenalty_ = tickData.totalPos != 0 ? tickData.liquidationPenalty : s._liquidationPenalty;
    }

    /**
     * @dev Converts the given bitmap index to a tick number using the stored tick spacing.
     * @param index The index into the bitmap.
     * @return tick_ The tick corresponding to the index, a multiple of the tick spacing.
     */
    function _calcTickFromBitmapIndex(uint256 index) internal view returns (int24 tick_) {
        Types.Storage storage s = Utils._getMainStorage();

        tick_ = _calcTickFromBitmapIndex(index, s._tickSpacing);
    }

    /**
     * @notice Calculates the unadjusted price of a position's liquidation price, which can be used to find the
     * corresponding tick.
     * @param price An adjusted liquidation price (taking into account the effects of funding).
     * @param assetPrice The current price of the asset.
     * @param longTradingExpo The trading exposure of the long side (total exposure - balance long).
     * @param accumulator The liquidation multiplier accumulator.
     * @return unadjustedPrice_ The unadjusted price of `price`.
     */
    function _unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal pure returns (uint256 unadjustedPrice_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return price;
        }
        if (longTradingExpo == 0) {
            // it is not possible to calculate the unadjusted price when the trading exposure is zero
            revert IUsdnProtocolErrors.UsdnProtocolZeroLongTradingExpo();
        }
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        // unadjustedPrice = price / M
        // unadjustedPrice = price * accumulator / (assetPrice * (totalExpo - balanceLong))
        HugeUint.Uint512 memory numerator = accumulator.mul(price);
        unadjustedPrice_ = numerator.div(assetPrice * longTradingExpo);
    }

    /**
     * @notice Calculates the unadjusted price of a position's liquidation price, which can be used to find the
     * corresponding tick, with a fixed precision representation of the liquidation multiplier.
     * @param price An adjusted liquidation price (taking into account the effects of funding).
     * @param liqMultiplier The liquidation price multiplier, with `LIQUIDATION_MULTIPLIER_DECIMALS` decimals.
     * @return unadjustedPrice_ The unadjusted price for the liquidation price.
     */
    function _unadjustPrice(uint256 price, uint256 liqMultiplier) internal pure returns (uint256 unadjustedPrice_) {
        // unadjustedPrice = price / M
        // unadjustedPrice = price * 10 ** LIQUIDATION_MULTIPLIER_DECIMALS / liqMultiplier
        unadjustedPrice_ =
            FixedPointMathLib.fullMulDiv(price, 10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS, liqMultiplier);
    }

    /**
     * @notice Calculates the value of a tick, knowing its contained total exposure and the current asset price.
     * @param tick The tick number.
     * @param currentPrice The current price of the asset.
     * @param longTradingExpo The trading exposure of the long side.
     * @param accumulator The liquidation multiplier accumulator.
     * @param tickData The aggregated data of the tick.
     * @return value_ The amount of asset tokens the tick is worth.
     */
    function _tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        Types.TickData memory tickData
    ) internal pure returns (int256 value_) {
        uint128 liqPriceWithoutPenalty = Utils._getEffectivePriceForTick(
            Utils._calcTickWithoutPenalty(tick, tickData.liquidationPenalty), currentPrice, longTradingExpo, accumulator
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
     * @notice Calculates the liquidation price without penalty of a position to reach a certain trading exposure.
     * @dev If the sum of `amount` and `tradingExpo` equals 0, reverts.
     * @param currentPrice The price of the asset.
     * @param amount The amount of asset used as collateral.
     * @param tradingExpo The trading exposure.
     * @return liqPrice_ The liquidation price without penalty.
     */
    function _calcLiqPriceFromTradingExpo(uint128 currentPrice, uint128 amount, uint256 tradingExpo)
        internal
        pure
        returns (uint128 liqPrice_)
    {
        uint256 totalExpo = amount + tradingExpo;
        if (totalExpo == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroTotalExpo();
        }

        liqPrice_ = FixedPointMathLib.fullMulDiv(currentPrice, tradingExpo, totalExpo).toUint128();
    }

    /**
     * @dev Converts a bitmap index to a tick number using the provided tick spacing.
     * @param index The index into the bitmap.
     * @param tickSpacing The tick spacing to use.
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`.
     */
    function _calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) internal pure returns (int24 tick_) {
        tick_ = int24( // cast to int24 is safe as index + TickMath.MIN_TICK cannot be above or below int24 limits
            (
                int256(index) // cast to int256 is safe as the index is lower than type(int24).max
                    + TickMath.MIN_TICK // shift into negative
                        / tickSpacing
            ) * tickSpacing
        );
    }

    /**
     * @notice Handles negative balances by transferring assets from one side to the other.
     * @dev Balances are unsigned integers and can't be negative.
     * In theory, this can not happen anymore because we have more precise calculations with the
     * `liqMultiplierAccumulator` compared to the old `liquidationMultiplier`.
     * @param tempLongBalance The temporary long balance after liquidations
     * @param tempVaultBalance The temporary vault balance after liquidations
     * @return longBalance_ The new long balance after rebalancing
     * @return vaultBalance_ The new vault balance after rebalancing
     */
    function _handleNegativeBalances(int256 tempLongBalance, int256 tempVaultBalance)
        internal
        pure
        returns (uint256 longBalance_, uint256 vaultBalance_)
    {
        // this can happen if the funding is larger than the remaining balance in the long side after applying PnL
        // test case: test_assetToTransferZeroBalance()
        if (tempLongBalance < 0) {
            tempVaultBalance += tempLongBalance;
            tempLongBalance = 0;
        }

        // this can happen if there is not enough balance in the vault to pay the bad debt in the long side, for
        // example if the protocol fees reduce the vault balance
        // test case: test_funding_NegLong_ZeroVault()
        if (tempVaultBalance < 0) {
            tempLongBalance += tempVaultBalance;
            tempVaultBalance = 0;
        }

        // in case one of the balances is still negative, clamp it to 0
        if (tempLongBalance < 0) {
            tempLongBalance = 0;
        }
        if (tempVaultBalance < 0) {
            tempVaultBalance = 0;
        }

        longBalance_ = tempLongBalance.toUint256();
        vaultBalance_ = tempVaultBalance.toUint256();
    }

    /**
     * @notice Calculates the current imbalance for the open action checks.
     * @dev If the value is positive, the long trading exposure is larger than the vault trading exposure.
     * In case of an empty vault balance, returns `int256.max` since the resulting imbalance would be infinity.
     * @param vaultExpo The vault exposure (including the pending vault balance and the fees of the position to open).
     * @param longBalance The balance of the long side (including the long position to open).
     * @param totalExpo The total exposure of the long side (including the long position to open).
     * @return imbalanceBps_ The imbalance (in basis points).
     */
    function _calcImbalanceOpenBps(int256 vaultExpo, int256 longBalance, uint256 totalExpo)
        internal
        pure
        returns (int256 imbalanceBps_)
    {
        // an imbalance cannot be calculated if the new vault exposure is zero or negative
        if (vaultExpo <= 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }

        // imbalanceBps = (longTradingExpo - vaultExpo) / vaultExpo
        // imbalanceBps = ((totalExpo - longBalance) - vaultExpo) / vaultExpo;
        imbalanceBps_ = (totalExpo.toInt256() - longBalance).safeSub(vaultExpo).safeMul(int256(Constants.BPS_DIVISOR))
            .safeDiv(vaultExpo);
    }

    /**
     * @notice Calculates the tick corresponding to an unadjusted price, without rounding to the tick spacing.
     * @param unadjustedPrice The unadjusted price.
     * @return tick_ The tick number, bound by `MIN_TICK`.
     */
    function _unadjustedPriceToTick(uint256 unadjustedPrice) internal pure returns (int24 tick_) {
        if (unadjustedPrice < TickMath.MIN_PRICE) {
            return TickMath.MIN_TICK;
        }

        tick_ = TickMath.getTickAtPrice(unadjustedPrice);
    }

    /**
     * @notice Rounds a tick down to a multiple of the tick spacing.
     * @dev The function is bound by {minTick}, so the first tick which is a multiple of the tick spacing
     * and greater than or equal to `MIN_TICK`.
     * @param tick The tick number.
     * @param tickSpacing The tick spacing.
     * @return roundedTick_ The rounded tick number.
     */
    function _roundTickDown(int24 tick, int24 tickSpacing) internal pure returns (int24 roundedTick_) {
        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            roundedTick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks
            int24 minUsableTick = TickMath.minUsableTick(tickSpacing);
            if (roundedTick_ < minUsableTick) {
                roundedTick_ = minUsableTick;
            }
        } else {
            // rounding is desirable here
            // slither-disable-next-line divide-before-multiply
            roundedTick_ = (tick / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Rounds the given tick down to a multiple of the tick spacing .
     * @dev The result will always be above `MIN_TICK` + liquidationPenalty.
     * @param tickWithPenalty The tick number with the liquidation penalty.
     * @param tickSpacing The tick spacing.
     * @param liqPenalty The liquidation penalty.
     * @return roundedTick_ The rounded tick number.
     */
    function _roundTickDownWithPenalty(int24 tickWithPenalty, int24 tickSpacing, uint24 liqPenalty)
        internal
        pure
        returns (int24 roundedTick_)
    {
        if (tickWithPenalty < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            roundedTick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tickWithPenalty)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks: we should be able to get the price for `tickWithPenalty_ - liquidationPenalty`
            int24 minTickWithPenalty = TickMath.MIN_TICK + int24(liqPenalty);
            if (roundedTick_ < minTickWithPenalty) {
                roundedTick_ = minTickWithPenalty - (minTickWithPenalty % tickSpacing);
            }
        } else {
            // rounding is desirable here
            // slither-disable-next-line divide-before-multiply
            roundedTick_ = (tickWithPenalty / tickSpacing) * tickSpacing;
        }
    }

    /**
     * @notice Calculates the effective tick for a given price without rounding to the tick spacing.
     * @param price The price to be adjusted.
     * @param assetPrice The current asset price.
     * @param longTradingExpo The long trading exposure.
     * @param accumulator The liquidation multiplier accumulator.
     * @return tick_ The tick number.
     */
    function _getEffectiveTickForPriceNoRounding(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal pure returns (int24 tick_) {
        // unadjust price with liquidation multiplier
        uint256 unadjustedPrice = _unadjustPrice(price, assetPrice, longTradingExpo, accumulator);
        tick_ = _unadjustedPriceToTick(unadjustedPrice);
    }

    /**
     * @notice Calculates the effective tick for a given price without rounding to the tick spacing with a fixed
     * precision representation of the liquidation multiplier.
     * @param price The price to be adjusted.
     * @param liqMultiplier The liquidation price multiplier (with `LIQUIDATION_MULTIPLIER_DECIMALS` decimals).
     * @return tick_ The tick number.
     */
    function _getEffectiveTickForPriceNoRounding(uint128 price, uint256 liqMultiplier)
        internal
        pure
        returns (int24 tick_)
    {
        // unadjust price with liquidation multiplier
        uint256 unadjustedPrice = _unadjustPrice(price, liqMultiplier);
        tick_ = _unadjustedPriceToTick(unadjustedPrice);
    }

    /**
     * @notice Calculates the required USDN total supply to reach `targetPrice`.
     * @param vaultBalance The balance of the vault.
     * @param assetPrice The price of the underlying asset.
     * @param targetPrice The target USDN price to reach.
     * @param assetDecimals The number of decimals of the asset.
     * @return totalSupply_ The required total supply to achieve `targetPrice`.
     */
    function _calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        internal
        pure
        returns (uint256 totalSupply_)
    {
        totalSupply_ = FixedPointMathLib.fullMulDiv(
            vaultBalance,
            uint256(assetPrice) * 10 ** Constants.TOKENS_DECIMALS,
            uint256(targetPrice) * 10 ** assetDecimals
        );
    }
}
