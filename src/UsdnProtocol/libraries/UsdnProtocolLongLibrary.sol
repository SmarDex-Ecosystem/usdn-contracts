// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IBaseRebalancer } from "../../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolLong } from "../../interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as ActionsVault } from "./UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolUtils as Utils } from "./UsdnProtocolUtils.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolLongLibrary {
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using SafeTransferLib for address;

    /**
     * @notice Structure to hold the temporary data during liquidation
     * @param tempLongBalance The temporary long balance
     * @param tempVaultBalance The temporary vault balance
     * @param currentTick The current tick (tick corresponding to the current asset price)
     * @param iTick Tick iterator index
     * @param totalExpoToRemove The total expo to remove due to the liquidation of some ticks
     * @param accumulatorValueToRemove The value to remove from the liquidation multiplier accumulator, due to the
     * liquidation of some ticks
     * @param longTradingExpo The long trading expo
     * @param currentPrice The current price of the asset
     * @param accumulator The liquidation multiplier accumulator before the liquidation
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
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
     * @notice Data structure for the `_applyPnlAndFundingAndLiquidate` function
     * @param isPriceRecent A boolean indicating if the price is recent
     * @param tempLongBalance The temporary long balance
     * @param tempVaultBalance The temporary vault balance
     * @param rebased A boolean indicating if the USDN token was rebased
     * @param rebalancerTriggered A boolean indicating if the rebalancer was triggered
     * @param callbackResult The result of the callback
     */
    struct ApplyPnlAndFundingAndLiquidateData {
        bool isPriceRecent;
        int256 tempLongBalance;
        int256 tempVaultBalance;
        uint128 lastPrice;
        bool rebased;
        bool rebalancerTriggered;
        bytes callbackResult;
    }

    /**
     * @notice Data structure for the `_triggerRebalancer` function
     * @param positionAmount The amount of assets in the rebalancer
     * @param rebalancerMaxLeverage The maximum leverage of the rebalancer
     * @param rebalancerPosId The ID of the rebalancer position
     * @param positionValue The value of the rebalancer position
     */
    struct TriggerRebalancerData {
        uint128 positionAmount;
        uint256 rebalancerMaxLeverage;
        Types.PositionId rebalancerPosId;
        uint128 positionValue;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolLong}
    function minTick(Types.Storage storage s) public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(s._tickSpacing);
    }

    /// @notice See {IUsdnProtocolLong}
    function maxTick(Types.Storage storage s) public view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(s._tickSpacing);
    }

    /// @notice See {IUsdnProtocolLong}
    function getLongPosition(Types.Storage storage s, Types.PositionId memory posId)
        public
        view
        returns (Types.Position memory pos_, uint24 liquidationPenalty_)
    {
        (bytes32 tickHash, uint256 version) = Core._tickHash(s, posId.tick);
        if (posId.tickVersion != version) {
            revert IUsdnProtocolErrors.UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        pos_ = s._longPositions[tickHash][posId.index];
        liquidationPenalty_ = s._tickData[tickHash].liquidationPenalty;
    }

    /// @notice See {IUsdnProtocolLong}
    function getPositionValue(
        Types.Storage storage s,
        Types.PositionId calldata posId,
        uint128 price,
        uint128 timestamp
    ) public view returns (int256 value_) {
        (Types.Position memory pos, uint24 liquidationPenalty) = getLongPosition(s, posId);
        int256 longTradingExpo = Core.longTradingExpoWithFunding(s, price, timestamp);
        if (longTradingExpo < 0) {
            // in case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // in this case, the liquidation price will fall to zero, and the position value will be equal to its
            // total expo (initial collateral * initial leverage)
            longTradingExpo = 0;
        }
        uint128 liqPrice = getEffectivePriceForTick(
            Utils.calcTickWithoutPenalty(posId.tick, liquidationPenalty),
            price,
            uint256(longTradingExpo),
            s._liqMultiplierAccumulator
        );
        value_ = _positionValue(price, liqPrice, pos.totalExpo);
    }

    /// @notice See {IUsdnProtocolLong}
    function getEffectiveTickForPrice(Types.Storage storage s, uint128 price) public view returns (int24 tick_) {
        tick_ = getEffectiveTickForPrice(
            price, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator, s._tickSpacing
        );
    }

    /// @notice See {IUsdnProtocolLong}
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

    /// @notice See {IUsdnProtocolLong}
    function getEffectivePriceForTick(Types.Storage storage s, int24 tick) public view returns (uint128 price_) {
        price_ =
            getEffectivePriceForTick(tick, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator);
    }

    /// @notice See {IUsdnProtocolLong}
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), assetPrice, longTradingExpo, accumulator);
    }

    /// @notice See {IUsdnProtocolLong}
    function getTickLiquidationPenalty(Types.Storage storage s, int24 tick)
        public
        view
        returns (uint24 liquidationPenalty_)
    {
        (bytes32 tickHash,) = Core._tickHash(s, tick);
        liquidationPenalty_ = _getTickLiquidationPenalty(s, tickHash);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Calculate the effective tick for a given price without rounding to the tick spacing
     * @param price The price to be adjusted
     * @param assetPrice The current asset price
     * @param longTradingExpo The long trading expo
     * @param accumulator The liquidation multiplier accumulator
     * @return tick_ The tick number
     */
    function _getEffectiveTickForPriceNoRounding(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public pure returns (int24 tick_) {
        // unadjust price with liquidation multiplier
        uint256 unadjustedPrice = _unadjustPrice(price, assetPrice, longTradingExpo, accumulator);
        tick_ = _unadjustedPriceToTick(unadjustedPrice);
    }

    /**
     * @notice Variant of `_getEffectiveTickForPriceNoRounding` when a fixed precision representation of the liquidation
     * multiplier is known
     * @param price The price to be adjusted
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return tick_ The tick number
     */
    function _getEffectiveTickForPriceNoRounding(uint128 price, uint256 liqMultiplier)
        public
        pure
        returns (int24 tick_)
    {
        // unadjust price with liquidation multiplier
        uint256 unadjustedPrice = _unadjustPrice(price, liqMultiplier);
        tick_ = _unadjustedPriceToTick(unadjustedPrice);
    }

    /**
     * @notice For a desired liquidation price, get the tick number with penalty and liquidation price without penalty
     * @dev This function first calculates a tick for the desired liq price (no rounding), then adds the penalty to the
     * tick and rounds down to the nearest tick spacing. Then it subtracts the penalty from the final tick and
     * calculates the corresponding liquidation price
     * @param s The storage of the protocol
     * @param desiredLiqPriceWithoutPenalty The desired liquidation price without penalty
     * @param liquidationPenalty The liquidation penalty
     * @return tickWithPenalty_ The tick number with penalty
     * @return liqPriceWithoutPenalty_ The liquidation price without penalty
     */
    function _getTickFromDesiredLiqPrice(
        Types.Storage storage s,
        uint128 desiredLiqPriceWithoutPenalty,
        uint24 liquidationPenalty
    ) public view returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
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
     * @notice For a desired liquidation price, get the tick number with penalty and liquidation price without penalty
     * @dev This function first calculates a tick for the desired liq price (no rounding), then adds the penalty to the
     * tick and rounds down to the nearest tick spacing. Then it subtracts the penalty from the final tick and
     * calculates the corresponding liquidation price
     * @param desiredLiqPriceWithoutPenalty The desired liquidation price without penalty
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @param tickSpacing The tick spacing
     * @param liquidationPenalty The liquidation penalty
     * @return tickWithPenalty_ The tick number with penalty
     * @return liqPriceWithoutPenalty_ The liquidation price without penalty
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
        liqPriceWithoutPenalty_ = getEffectivePriceForTick(
            Utils.calcTickWithoutPenalty(tickWithPenalty_, liquidationPenalty), assetPrice, longTradingExpo, accumulator
        );
    }

    /**
     * @notice For a desired liquidation price, get the tick number with penalty and liquidation price without penalty
     * @dev This function first calculates a tick for the desired liq price (no rounding), then adds the penalty to the
     * tick and rounds down to the nearest tick spacing. Then it subtracts the penalty from the final tick and
     * calculates the corresponding liquidation price
     * @param desiredLiqPriceWithoutPenalty The desired liquidation price without penalty
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @param tickSpacing The tick spacing
     * @param liquidationPenalty The liquidation penalty
     * @return tickWithPenalty_ The tick number with penalty
     * @return liqPriceWithoutPenalty_ The liquidation price without penalty
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
        liqPriceWithoutPenalty_ =
            _getEffectivePriceForTick(Utils.calcTickWithoutPenalty(tickWithPenalty_, liquidationPenalty), liqMultiplier);
    }

    /**
     * @notice Applies PnL, funding, and liquidates positions if necessary
     * @param s The storage of the protocol
     * @param neutralPrice The neutral price for the asset
     * @param timestamp The timestamp at which the operation is performed
     * @param iterations The number of iterations for the liquidation process
     * @param ignoreInterval A boolean indicating whether to ignore the interval for USDN rebase
     * @param action The type of action that is being performed by the user
     * @param priceData The price oracle update data
     * @return liquidatedPositions_ The number of positions that were liquidated
     * @return isLiquidationPending_ If there are pending positions to liquidate
     * @dev If there were any liquidated positions, it sends rewards to the msg.sender
     */
    function _applyPnlAndFundingAndLiquidate(
        Types.Storage storage s,
        uint256 neutralPrice,
        uint256 timestamp,
        uint16 iterations,
        bool ignoreInterval,
        Types.ProtocolAction action,
        bytes calldata priceData
    ) public returns (uint256 liquidatedPositions_, bool isLiquidationPending_) {
        ApplyPnlAndFundingAndLiquidateData memory data;
        {
            Types.ApplyPnlAndFundingData memory temporaryData =
                Core._applyPnlAndFunding(s, neutralPrice.toUint128(), timestamp.toUint128());
            assembly {
                mcopy(data, temporaryData, 128)
            }
        }

        // liquidate if the price was updated or was already the most recent
        if (data.isPriceRecent) {
            Types.LiquidationsEffects memory liquidationEffects =
                _liquidatePositions(s, data.lastPrice, iterations, data.tempLongBalance, data.tempVaultBalance);

            isLiquidationPending_ = liquidationEffects.isLiquidationPending;
            if (!isLiquidationPending_ && liquidationEffects.liquidatedTicks > 0) {
                if (s._closeExpoImbalanceLimitBps > 0) {
                    (liquidationEffects.newLongBalance, liquidationEffects.newVaultBalance) = _triggerRebalancer(
                        s,
                        data.lastPrice,
                        liquidationEffects.newLongBalance,
                        liquidationEffects.newVaultBalance,
                        liquidationEffects.remainingCollateral
                    );
                    data.rebalancerTriggered = true;
                }
            }

            s._balanceLong = liquidationEffects.newLongBalance;
            s._balanceVault = liquidationEffects.newVaultBalance;

            (data.rebased, data.callbackResult) = Vault._usdnRebase(s, data.lastPrice, ignoreInterval);

            if (liquidationEffects.liquidatedTicks > 0) {
                ActionsUtils._sendRewardsToLiquidator(
                    s,
                    liquidationEffects.liquidatedTicks,
                    liquidationEffects.remainingCollateral,
                    data.rebased,
                    data.rebalancerTriggered,
                    action,
                    data.callbackResult,
                    priceData
                );
            }

            liquidatedPositions_ = liquidationEffects.liquidatedPositions;
        }
    }

    /**
     * @notice Trigger the rebalancer if the imbalance on the long side is too high
     * It will close the rebalancer position (if there is one) and open a new one with
     * the pending assets, the value of the previous position and the liquidation bonus (if available)
     * and a leverage to fill enough trading expo to reach the desired imbalance, up to the max leverages
     * @dev Will return the provided long balance if no rebalancer is set or if the imbalance is not high enough
     * @param s The storage of the protocol
     * @param lastPrice The last price used to update the protocol
     * @param longBalance The balance of the long side
     * @param vaultBalance The balance of the vault side
     * @param remainingCollateral The collateral remaining after the liquidations
     * @return longBalance_ The temporary balance of the long side
     * @return vaultBalance_ The temporary balance of the vault side
     */
    function _triggerRebalancer(
        Types.Storage storage s,
        uint128 lastPrice,
        uint256 longBalance,
        uint256 vaultBalance,
        int256 remainingCollateral
    ) public returns (uint256 longBalance_, uint256 vaultBalance_) {
        longBalance_ = longBalance;
        vaultBalance_ = vaultBalance;
        IBaseRebalancer rebalancer = s._rebalancer;

        if (address(rebalancer) == address(0)) {
            return (longBalance_, vaultBalance_);
        }

        Types.CachedProtocolState memory cache = Types.CachedProtocolState({
            totalExpo: s._totalExpo,
            longBalance: longBalance,
            vaultBalance: (vaultBalance.toInt256() + s._pendingBalanceVault).toUint256(),
            tradingExpo: 0,
            liqMultiplierAccumulator: s._liqMultiplierAccumulator
        });

        if (cache.totalExpo < cache.longBalance) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo();
        }

        cache.tradingExpo = cache.totalExpo - cache.longBalance;

        // calculate the bonus now and update the cache to make sure removing it from the vault doesn't push the
        // imbalance above the threshold
        uint128 bonus;
        if (remainingCollateral > 0) {
            bonus = (uint256(remainingCollateral) * s._rebalancerBonusBps / Constants.BPS_DIVISOR).toUint128();
            cache.vaultBalance -= bonus;
        }

        {
            int256 currentImbalance =
                _calcImbalanceCloseBps(cache.vaultBalance.toInt256(), cache.longBalance.toInt256(), cache.totalExpo);

            // if the imbalance is lower than the threshold, return
            if (currentImbalance < s._closeExpoImbalanceLimitBps) {
                return (longBalance_, vaultBalance_);
            }
        }

        TriggerRebalancerData memory data;
        // the default value of `positionAmount` is the amount of pendingAssets in the rebalancer
        (data.positionAmount, data.rebalancerMaxLeverage, data.rebalancerPosId) = rebalancer.getCurrentStateData();

        // close the rebalancer position and get its value to open the next one
        if (data.rebalancerPosId.tick != Constants.NO_POSITION_TICK) {
            // cached values will be updated during this call
            int256 realPositionValue = _flashClosePosition(s, data.rebalancerPosId, lastPrice, cache);

            // if the position value is less than 0, it should have been liquidated but wasn't
            // interrupt the whole rebalancer process because there are pending liquidations
            if (realPositionValue < 0) {
                return (longBalance_, vaultBalance_);
            }

            // cast is safe as realPositionValue cannot be lower than 0
            data.positionValue = uint256(realPositionValue).toUint128();
            data.positionAmount += data.positionValue;
            longBalance_ -= data.positionValue;
        } else if (data.positionAmount == 0) {
            // avoid to update an empty rebalancer
            return (longBalance_, vaultBalance_);
        }

        // if the amount in the position we wanted to open is below a fraction of the _minLongPosition setting,
        // we are dealing with dust. So we should stop the process and gift the remaining value to the vault
        if (data.positionAmount <= s._minLongPosition / 10_000) {
            // make the rebalancer believe that the previous position was liquidated,
            // and inform it that no new position was open so it can start anew
            rebalancer.updatePosition(Types.PositionId(Constants.NO_POSITION_TICK, 0, 0), 0);
            vaultBalance_ += data.positionAmount;
            return (longBalance_, vaultBalance_);
        }

        // transfer the pending assets from the rebalancer to this contract
        // slither-disable-next-line arbitrary-send-erc20
        address(s._asset).safeTransferFrom(address(rebalancer), address(this), data.positionAmount - data.positionValue);

        // add the bonus to the new rebalancer position and remove it from the vault
        if (bonus > 0) {
            vaultBalance_ -= bonus;
            data.positionAmount += bonus;
        }

        Types.RebalancerPositionData memory posData =
            _calcRebalancerPositionTick(s, lastPrice, data.positionAmount, data.rebalancerMaxLeverage, cache);

        // make sure that the rebalancer was not triggered without a sufficient imbalance
        // as we check the imbalance above, this should not happen
        if (posData.tick == Constants.NO_POSITION_TICK) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerTick();
        }

        // open a new position for the rebalancer
        Types.PositionId memory posId = _flashOpenPosition(
            s,
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
    }

    /**
     * @notice Immediately open a position with the given price
     * @dev Should only be used to open the rebalancer position
     * @param s The storage of the protocol
     * @param user The address of the user
     * @param lastPrice The last price used to update the protocol
     * @param tick The tick the position should be opened in
     * @param posTotalExpo The position total expo
     * @param liquidationPenalty The liquidation penalty of the tick
     * @param amount The amount of collateral in the position
     * @return posId_ The ID of the position that was created
     */
    function _flashOpenPosition(
        Types.Storage storage s,
        address user,
        uint128 lastPrice,
        int24 tick,
        uint128 posTotalExpo,
        uint24 liquidationPenalty,
        uint128 amount
    ) public returns (Types.PositionId memory posId_) {
        posId_.tick = tick;
        Types.Position memory long = Types.Position({
            validated: true,
            user: user,
            amount: amount,
            totalExpo: posTotalExpo,
            timestamp: uint40(block.timestamp)
        });

        // save the position on the provided tick
        (posId_.tickVersion, posId_.index,) = ActionsUtils._saveNewPosition(s, posId_.tick, long, liquidationPenalty);

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        emit IUsdnProtocolEvents.InitiatedOpenPosition(
            user, user, uint40(block.timestamp), posTotalExpo, long.amount, lastPrice, posId_
        );
        emit IUsdnProtocolEvents.ValidatedOpenPosition(user, user, posTotalExpo, lastPrice, posId_);
    }

    /**
     * @notice Immediately close a position with the given price
     * @dev Should only be used to close the rebalancer position
     * @param s The storage of the protocol
     * @param posId The ID of the position to close
     * @param lastPrice The last price used to update the protocol
     * @param cache The cached state of the protocol, will be updated during this call
     * @return positionValue_ The value of the closed position
     */
    function _flashClosePosition(
        Types.Storage storage s,
        Types.PositionId memory posId,
        uint128 lastPrice,
        Types.CachedProtocolState memory cache
    ) public returns (int256 positionValue_) {
        (bytes32 tickHash, uint256 version) = Core._tickHash(s, posId.tick);
        // if the tick version is outdated, the position was liquidated and its value is 0
        if (posId.tickVersion != version) {
            return positionValue_;
        }

        uint24 liquidationPenalty = s._tickData[tickHash].liquidationPenalty;
        Types.Position memory pos = s._longPositions[tickHash][posId.index];

        positionValue_ = _positionValue(
            lastPrice,
            getEffectivePriceForTick(
                Utils.calcTickWithoutPenalty(posId.tick, liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            ),
            pos.totalExpo
        );

        // if positionValue is lower than 0, return
        if (positionValue_ < 0) {
            return positionValue_;
        }

        // fully close the position and update the cache
        cache.liqMultiplierAccumulator =
            ActionsUtils._removeAmountFromPosition(s, posId.tick, posId.index, pos, pos.amount, pos.totalExpo);

        // update the cache
        cache.totalExpo -= pos.totalExpo;
        // cast is safe as positionValue cannot be lower than 0
        cache.longBalance -= uint256(positionValue_);
        cache.tradingExpo = cache.totalExpo - cache.longBalance;

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        emit IUsdnProtocolEvents.InitiatedClosePosition(pos.user, pos.user, pos.user, posId, pos.amount, pos.amount, 0);
        emit IUsdnProtocolEvents.ValidatedClosePosition(
            pos.user, pos.user, posId, uint256(positionValue_), positionValue_ - Utils.toInt256(pos.amount)
        );
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate open position action
     * @dev Reverts if the imbalance limit is reached, or if the safety margin is not respected
     * @param s The storage of the protocol
     * @param validator The address of the validator
     * @param amount The amount of wstETH to deposit
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty
     * @param currentPriceData The current price data
     * @return data_ The temporary data for the open position action
     */
    function _prepareInitiateOpenPositionData(
        Types.Storage storage s,
        address validator,
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) public returns (Types.InitiateOpenPositionData memory data_) {
        PriceInfo memory currentPrice = ActionsVault._getOraclePrice(
            s,
            Types.ProtocolAction.InitiateOpenPosition,
            block.timestamp,
            ActionsUtils._calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );
        data_.adjustedPrice =
            (currentPrice.price + currentPrice.price * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();

        uint128 neutralPrice = currentPrice.neutralPrice.toUint128();

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            Types.ProtocolAction.InitiateOpenPosition,
            currentPriceData
        );

        // early return in case there are still pending liquidations
        if (data_.isLiquidationPending) {
            return data_;
        }

        // gas savings, we only load the data once and use it for all conversions below
        Types.TickPriceConversionData memory conversionData = Types.TickPriceConversionData({
            assetPrice: s._lastPrice,
            tradingExpo: s._totalExpo - s._balanceLong,
            accumulator: s._liqMultiplierAccumulator,
            tickSpacing: s._tickSpacing
        });
        // we calculate the closest valid tick down for the desired liq price with liquidation penalty
        data_.posId.tick = getEffectiveTickForPrice(
            desiredLiqPrice,
            conversionData.assetPrice,
            conversionData.tradingExpo,
            conversionData.accumulator,
            conversionData.tickSpacing
        );
        data_.liquidationPenalty = getTickLiquidationPenalty(s, data_.posId.tick);

        // calculate effective liquidation price
        uint128 liqPrice = getEffectivePriceForTick(
            data_.posId.tick, conversionData.assetPrice, conversionData.tradingExpo, conversionData.accumulator
        );

        // liquidation price must be at least x% below the current price
        _checkSafetyMargin(s, neutralPrice, liqPrice);

        // remove liquidation penalty for leverage and total expo calculations
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(
            Utils.calcTickWithoutPenalty(data_.posId.tick, data_.liquidationPenalty),
            conversionData.assetPrice,
            conversionData.tradingExpo,
            conversionData.accumulator
        );
        _checkOpenPositionLeverage(s, data_.adjustedPrice, liqPriceWithoutPenalty);

        data_.positionTotalExpo = _calcPositionTotalExpo(amount, data_.adjustedPrice, liqPriceWithoutPenalty);
        // the current price is known to be above the liquidation price because we checked the safety margin
        // the `currentPrice.price` value can safely be cast to uint128 because we already did so above after the
        // `adjustedPrice` calculation
        data_.positionValue =
            Utils.positionValue(data_.positionTotalExpo, uint128(currentPrice.price), liqPriceWithoutPenalty);
        _checkImbalanceLimitOpen(s, data_.positionTotalExpo, amount);

        data_.liqMultiplier = _calcFixedPrecisionMultiplier(
            conversionData.assetPrice, conversionData.tradingExpo, conversionData.accumulator
        );
    }

    /**
     * @notice Reverts if the position's leverage is higher than max or lower than min
     * @param s The storage of the protocol
     * @param adjustedPrice The adjusted price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     */
    function _checkOpenPositionLeverage(Types.Storage storage s, uint128 adjustedPrice, uint128 liqPriceWithoutPenalty)
        public
        view
    {
        // calculate position leverage
        // reverts if liquidationPrice >= entryPrice
        uint256 leverage = _getLeverage(adjustedPrice, liqPriceWithoutPenalty);
        if (leverage < s._minLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolLeverageTooLow();
        }
        if (leverage > s._maxLeverage) {
            revert IUsdnProtocolErrors.UsdnProtocolLeverageTooHigh();
        }
    }

    /**
     * @notice The open long imbalance limit state verification. Revert
     * @dev To ensure that the protocol does not imbalance more than
     * the open limit on the long side, otherwise revert
     * @param s The storage of the protocol
     * @param openTotalExpoValue The open position expo value
     * @param openCollatValue The open position collateral value
     */
    function _checkImbalanceLimitOpen(Types.Storage storage s, uint256 openTotalExpoValue, uint256 openCollatValue)
        public
        view
    {
        int256 openExpoImbalanceLimitBps = s._openExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (openExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault);
        int256 imbalanceBps = _calcImbalanceOpenBps(
            currentVaultExpo, (s._balanceLong + openCollatValue).toInt256(), s._totalExpo + openTotalExpoValue
        );

        if (imbalanceBps >= openExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Liquidate positions that have a liquidation price lower than the current price
     * @param s The storage of the protocol
     * @param currentPrice The current price of the asset
     * @param iteration The maximum number of ticks to liquidate (minimum is 1)
     * @param tempLongBalance The temporary long balance as calculated when applying the PnL and funding
     * @param tempVaultBalance The temporary vault balance as calculated when applying the PnL and funding
     * @return effects_ The effects of the liquidations on the protocol
     */
    function _liquidatePositions(
        Types.Storage storage s,
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) public returns (Types.LiquidationsEffects memory effects_) {
        int256 longTradingExpo = s._totalExpo.toInt256() - tempLongBalance;
        if (longTradingExpo <= 0) {
            // in case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // in this case, it's not possible to calculate the current tick, so we can't perform any liquidations
            (effects_.newLongBalance, effects_.newVaultBalance) =
                _handleNegativeBalances(tempLongBalance, tempVaultBalance);
            return effects_;
        }

        LiquidationData memory data;
        data.tempLongBalance = tempLongBalance;
        data.tempVaultBalance = tempVaultBalance;
        data.longTradingExpo = uint256(longTradingExpo);
        data.currentPrice = currentPrice;
        data.accumulator = s._liqMultiplierAccumulator;

        // max iteration limit
        if (iteration > Constants.MAX_LIQUIDATION_ITERATION) {
            iteration = Constants.MAX_LIQUIDATION_ITERATION;
        }

        uint256 unadjustedPrice =
            _unadjustPrice(data.currentPrice, data.currentPrice, data.longTradingExpo, data.accumulator);
        data.currentTick = TickMath.getClosestTickAtPrice(unadjustedPrice);
        data.iTick = s._highestPopulatedTick;

        do {
            uint256 index = s._tickBitmap.findLastSet(Core._calcBitmapIndexFromTick(s, data.iTick));
            if (index == LibBitmap.NOT_FOUND) {
                // no populated ticks left
                break;
            }

            data.iTick = _calcTickFromBitmapIndex(s, index);
            if (data.iTick < data.currentTick) {
                // all ticks that can be liquidated have been processed
                break;
            }

            // we have found a non-empty tick that needs to be liquidated
            (bytes32 tickHash,) = Core._tickHash(s, data.iTick);

            Types.TickData memory tickData = s._tickData[tickHash];
            // update transient data
            data.totalExpoToRemove += tickData.totalExpo;
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(Utils.calcTickWithoutPenalty(data.iTick, tickData.liquidationPenalty));
            data.accumulatorValueToRemove += unadjustedTickPrice * tickData.totalExpo;
            // update return values
            effects_.liquidatedPositions += tickData.totalPos;
            ++effects_.liquidatedTicks;
            int256 tickValue =
                _tickValue(data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator, tickData);
            effects_.remainingCollateral += tickValue;

            // reset tick by incrementing the tick version
            ++s._tickVersion[data.iTick];
            // update bitmap to reflect that the tick is empty
            s._tickBitmap.unset(index);

            emit IUsdnProtocolEvents.LiquidatedTick(
                data.iTick,
                s._tickVersion[data.iTick] - 1,
                data.currentPrice,
                getEffectivePriceForTick(data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator),
                tickValue
            );
        } while (effects_.liquidatedTicks < iteration);

        _updateStateAfterLiquidation(s, data, effects_); // mutates `data`
        effects_.isLiquidationPending = data.isLiquidationPending;
        (effects_.newLongBalance, effects_.newVaultBalance) =
            _handleNegativeBalances(data.tempLongBalance, data.tempVaultBalance);
    }

    /**
     * @notice Variant of `getEffectivePriceForTick` when a fixed precision representation of the liquidation multiplier
     * is known
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) public pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), liqMultiplier);
    }

    /**
     * @notice Variant of `getEffectiveTickForPrice` when a fixed precision representation of the liquidation multiplier
     * is known
     * @param price The price
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return tick_ The corresponding tick
     */
    function _getEffectiveTickForPrice(uint128 price, uint256 liqMultiplier, int24 tickSpacing)
        public
        pure
        returns (int24 tick_)
    {
        // unadjust price with liquidation multiplier
        uint256 unadjustedPrice = _unadjustPrice(price, liqMultiplier);

        if (unadjustedPrice < TickMath.MIN_PRICE) {
            return TickMath.minUsableTick(tickSpacing);
        }

        tick_ = TickMath.getTickAtPrice(unadjustedPrice);

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        tick_ = _roundTickDown(tick_, tickSpacing);
    }

    /**
     * @notice Knowing the liquidation price of a position, get the corresponding unadjusted price, which can be used
     * to find the corresponding tick
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
     * @notice Variant of _unadjustPrice when a fixed precision representation of the liquidation multiplier is known
     * @param price An adjusted liquidation price (taking into account the effects of funding)
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return unadjustedPrice_ The unadjusted price for the liquidation price
     */
    function _unadjustPrice(uint256 price, uint256 liqMultiplier) public pure returns (uint256 unadjustedPrice_) {
        // unadjustedPrice = price / M
        // unadjustedPrice = price * 10^LIQUIDATION_MULTIPLIER_DECIMALS / liqMultiplier
        unadjustedPrice_ =
            FixedPointMathLib.fullMulDiv(price, 10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS, liqMultiplier);
    }

    /**
     * @notice Knowing the unadjusted price for a tick, get the adjusted price taking into account the effects of the
     * funding
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
     * @notice Variant of _adjustPrice when a fixed precision representation of the liquidation multiplier is known
     * @param unadjustedPrice The unadjusted price for the tick
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _adjustPrice(uint256 unadjustedPrice, uint256 liqMultiplier) public pure returns (uint128 price_) {
        // price = unadjustedPrice * M
        price_ = FixedPointMathLib.fullMulDiv(
            unadjustedPrice, liqMultiplier, 10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS
        ).toUint128();
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
    ) public pure returns (uint256 multiplier_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return 10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS;
        }
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator =
            HugeUint.mul(10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS, assetPrice * longTradingExpo);
        multiplier_ = numerator.div(accumulator);
    }

    /**
     * @notice Find the highest tick that contains at least one position
     * @dev If there are no ticks with a position left, returns minTick()
     * @param s The storage of the protocol
     * @param searchStart The tick from which to start searching
     * @return tick_ The next highest tick below `searchStart`
     */
    function _findHighestPopulatedTick(Types.Storage storage s, int24 searchStart) public view returns (int24 tick_) {
        uint256 index = s._tickBitmap.findLastSet(Core._calcBitmapIndexFromTick(s, searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick(s);
        } else {
            tick_ = _calcTickFromBitmapIndex(s, index);
        }
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
     * @notice Calculate the value of a tick, knowing its contained total expo and the current asset price
     * @param tick The tick number
     * @param currentPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side
     * @param accumulator The liquidation multiplier accumulator
     * @param tickData The aggregate data for the tick
     * @return value_ The value of the tick (qty of asset tokens)
     */
    function _tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        Types.TickData memory tickData
    ) public pure returns (int256 value_) {
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(
            Utils.calcTickWithoutPenalty(tick, tickData.liquidationPenalty), currentPrice, longTradingExpo, accumulator
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
     * @notice Calculate the leverage of a position, knowing its start price and liquidation price
     * @dev This does not take into account the liquidation penalty
     * @param startPrice Entry price of the position
     * @param liquidationPrice Liquidation price of the position
     * @return leverage_ The leverage of the position
     */
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) public pure returns (uint256 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // also, the calculation below would underflow
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = (10 ** Constants.LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice);
    }

    /**
     * @notice Calculate the total exposure of a position
     * @dev Reverts when startPrice <= liquidationPrice
     * @param amount The amount of asset used as collateral
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return totalExpo_ The total exposure of a position
     */
    function _calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        public
        pure
        returns (uint128 totalExpo_)
    {
        if (startPrice <= liquidationPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        totalExpo_ = FixedPointMathLib.fullMulDiv(amount, startPrice, startPrice - liquidationPrice).toUint128();
    }

    /**
     * @notice Calculate the liquidation price without penalty of a position to reach a certain trading expo
     * @dev If the sum of `amount` and `tradingExpo` equals 0, reverts
     * @param currentPrice The price of the asset
     * @param amount The amount of asset
     * @param tradingExpo The trading expo
     * @return liqPrice_ The liquidation price without penalty
     */
    function _calcLiqPriceFromTradingExpo(uint128 currentPrice, uint128 amount, uint256 tradingExpo)
        public
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
     * @notice Check if the safety margin is respected
     * @dev Reverts if not respected
     * @param s The storage of the protocol
     * @param currentPrice The current price of the asset
     * @param liquidationPrice The liquidation price of the position
     */
    function _checkSafetyMargin(Types.Storage storage s, uint128 currentPrice, uint128 liquidationPrice) public view {
        uint128 maxLiquidationPrice =
            (currentPrice * (Constants.BPS_DIVISOR - s._safetyMarginBps) / Constants.BPS_DIVISOR).toUint128();
        if (liquidationPrice >= maxLiquidationPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    /**
     * @notice Retrieve the liquidation penalty assigned to the tick and version corresponding to `tickHash`, if there
     * are positions in it, otherwise retrieve the current setting value from storage
     * @dev This method allows to reuse a pre-computed tickHash if available
     * @param s The storage of the protocol
     * @param tickHash The tick hash
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function _getTickLiquidationPenalty(Types.Storage storage s, bytes32 tickHash)
        public
        view
        returns (uint24 liquidationPenalty_)
    {
        Types.TickData storage tickData = s._tickData[tickHash];
        liquidationPenalty_ = tickData.totalPos != 0 ? tickData.liquidationPenalty : s._liquidationPenalty;
    }

    /**
     * @dev Convert a Bitmap index to a signed tick using the tick spacing in storage
     * @param s The storage of the protocol
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of the tick spacing
     */
    function _calcTickFromBitmapIndex(Types.Storage storage s, uint256 index) public view returns (int24 tick_) {
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

    /**
     * @notice Update the state of the contract according to the liquidation effects
     * @param s The storage of the protocol
     * @param data The liquidation data, which gets mutated by the function
     * @param effects The effects of the liquidations
     */
    function _updateStateAfterLiquidation(
        Types.Storage storage s,
        LiquidationData memory data,
        Types.LiquidationsEffects memory effects
    ) public {
        // update the state
        s._totalLongPositions -= effects.liquidatedPositions;
        s._totalExpo -= data.totalExpoToRemove;
        s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.sub(HugeUint.wrap(data.accumulatorValueToRemove));

        // keep track of the highest populated tick
        if (effects.liquidatedPositions != 0) {
            int24 highestPopulatedTick;
            if (data.iTick < data.currentTick) {
                // all ticks above the current tick were liquidated
                highestPopulatedTick = _findHighestPopulatedTick(s, data.currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                highestPopulatedTick = _findHighestPopulatedTick(s, data.iTick);
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

        // TODO: remove safe cast once we're sure we can never have negative balances
        longBalance_ = tempLongBalance.toUint256();
        vaultBalance_ = tempVaultBalance.toUint256();
    }

    /**
     * @notice Calculates the current imbalance between the vault and long sides
     * @dev If the value is positive, the long trading expo is smaller than the vault trading expo
     * If the trading expo is equal to 0, the imbalance is infinite and int256.max is returned
     * @param vaultBalance The balance of the vault
     * @param longBalance The balance of the long side
     * @param totalExpo The total expo of the long side
     * @return imbalanceBps_ The imbalance in basis points
     */
    function _calcImbalanceCloseBps(int256 vaultBalance, int256 longBalance, uint256 totalExpo)
        public
        pure
        returns (int256 imbalanceBps_)
    {
        int256 tradingExpo = totalExpo.toInt256().safeSub(longBalance);
        if (tradingExpo == 0) {
            return type(int256).max;
        }

        // imbalanceBps_ = (vaultBalance - (totalExpo - longBalance)) *s. (totalExpo - longBalance);
        imbalanceBps_ = (vaultBalance.safeSub(tradingExpo)).safeMul(int256(Constants.BPS_DIVISOR)).safeDiv(tradingExpo);
    }

    /**
     * @notice Calculates the current imbalance for the open action checks
     * @dev If the value is positive, the long trading expo is larger than the vault trading expo
     * In case of zero vault balance, the function returns `int256.max` since the resulting imbalance would be infinity
     * @param vaultBalance The balance of the vault
     * @param longBalance The balance of the long side (including the long position to open)
     * @param totalExpo The total expo of the long side (including the long position to open)
     * @return imbalanceBps_ The imbalance in basis points
     */
    function _calcImbalanceOpenBps(int256 vaultBalance, int256 longBalance, uint256 totalExpo)
        public
        pure
        returns (int256 imbalanceBps_)
    {
        // avoid division by zero
        if (vaultBalance == 0) {
            return type(int256).max;
        }
        // imbalanceBps_ = ((totalExpo - longBalance) - vaultBalance) *s. vaultBalance;
        int256 longTradingExpo = totalExpo.toInt256() - longBalance;
        imbalanceBps_ =
            longTradingExpo.safeSub(vaultBalance).safeMul(int256(Constants.BPS_DIVISOR)).safeDiv(vaultBalance);
    }

    /**
     * @notice Calculates the tick of the rebalancer position to open
     * @dev The returned tick must give a leverage higher than or equal to the minimum leverage of the protocol
     * and lower than or equal to the rebalancer and USDN protocol leverages (lower of the 2)
     * @param s The storage of the protocol
     * @param lastPrice The last price used to update the protocol
     * @param positionAmount The amount of assets in the position
     * @param rebalancerMaxLeverage The max leverage supported by the rebalancer
     * @param cache The cached protocol state values
     * @return posData_ The tick, total expo and liquidation penalty for the rebalancer position
     */
    function _calcRebalancerPositionTick(
        Types.Storage storage s,
        uint128 lastPrice,
        uint128 positionAmount,
        uint256 rebalancerMaxLeverage,
        Types.CachedProtocolState memory cache
    ) public view returns (Types.RebalancerPositionData memory posData_) {
        Types.CalcRebalancerPositionTickData memory data;
        // use the lowest max leverage above the min leverage
        data.protocolMinLeverage = s._minLeverage;
        {
            data.protocolMaxLeverage = s._maxLeverage;
            if (rebalancerMaxLeverage > data.protocolMaxLeverage) {
                rebalancerMaxLeverage = data.protocolMaxLeverage;
            }
            if (rebalancerMaxLeverage < data.protocolMinLeverage) {
                rebalancerMaxLeverage = data.protocolMinLeverage;
            }
        }

        data.longImbalanceTargetBps = s._longImbalanceTargetBps;
        // calculate the trading expo missing to reach the imbalance target
        uint256 targetTradingExpo = (
            cache.vaultBalance * Constants.BPS_DIVISOR
                / (int256(Constants.BPS_DIVISOR) + data.longImbalanceTargetBps).toUint256()
        );

        // check that the target is not already exceeded
        if (cache.tradingExpo >= targetTradingExpo) {
            posData_.tick = Constants.NO_POSITION_TICK;
            return posData_;
        }

        uint256 tradingExpoToFill = targetTradingExpo - cache.tradingExpo;

        // check that the trading expo filled by the position would not exceed the max leverage
        data.highestUsableTradingExpo =
            positionAmount * rebalancerMaxLeverage / 10 ** Constants.LEVERAGE_DECIMALS - positionAmount;
        if (data.highestUsableTradingExpo < tradingExpoToFill) {
            tradingExpoToFill = data.highestUsableTradingExpo;
        }

        // check that the trading expo filled by the position would not be below the min leverage
        data.lowestUsableTradingExpo =
            positionAmount * data.protocolMinLeverage / 10 ** Constants.LEVERAGE_DECIMALS - positionAmount;
        if (data.lowestUsableTradingExpo > tradingExpoToFill) {
            tradingExpoToFill = data.lowestUsableTradingExpo;
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

        posData_.liquidationPenalty = getTickLiquidationPenalty(s, posData_.tick);
        if (posData_.liquidationPenalty != data.currentLiqPenalty) {
            data.liqPriceWithoutPenalty = getEffectivePriceForTick(
                Utils.calcTickWithoutPenalty(posData_.tick, posData_.liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            );
        }
        posData_.totalExpo = _calcPositionTotalExpo(positionAmount, lastPrice, data.liqPriceWithoutPenalty);

        // due to the rounding down, if the imbalance is still greater than the desired imbalance
        // and the position is not at the max leverage, add one tick
        if (
            data.highestUsableTradingExpo != tradingExpoToFill
                && _calcImbalanceCloseBps(
                    cache.vaultBalance.toInt256(),
                    (cache.longBalance + positionAmount).toInt256(),
                    cache.totalExpo + posData_.totalExpo
                ) > data.longImbalanceTargetBps
        ) {
            posData_.tick += s._tickSpacing;
            posData_.liquidationPenalty = getTickLiquidationPenalty(s, posData_.tick);
            data.liqPriceWithoutPenalty = getEffectivePriceForTick(
                Utils.calcTickWithoutPenalty(posData_.tick, posData_.liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            );
            posData_.totalExpo = _calcPositionTotalExpo(positionAmount, lastPrice, data.liqPriceWithoutPenalty);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              Private functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Calculate the tick corresponding to an unadjusted price, without rounding to the tick spacing
     * @param unadjustedPrice The unadjusted price
     * @return tick_ The tick number, bound by MIN_TICK
     */
    function _unadjustedPriceToTick(uint256 unadjustedPrice) private pure returns (int24 tick_) {
        if (unadjustedPrice < TickMath.MIN_PRICE) {
            return TickMath.MIN_TICK;
        }

        tick_ = TickMath.getTickAtPrice(unadjustedPrice);
    }

    /**
     * @notice Round a tick down to a multiple of the tick spacing
     * @dev The function is bound by the minimum usable tick, so the first tick which is a multiple of the tick spacing
     * and greater than or equal to MIN_TICK
     * @param tick The tick number
     * @param tickSpacing The tick spacing
     * @return roundedTick_ The rounded tick number
     */
    function _roundTickDown(int24 tick, int24 tickSpacing) private pure returns (int24 roundedTick_) {
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
     * @notice Round a tick down to a multiple of the tick spacing while remaining above MIN_TICK + liquidationPenalty
     * @param tickWithPenalty The tick number with the liquidation penalty
     * @param tickSpacing The tick spacing
     * @param liqPenalty The liquidation penalty
     * @return roundedTick_ The rounded tick number
     */
    function _roundTickDownWithPenalty(int24 tickWithPenalty, int24 tickSpacing, uint24 liqPenalty)
        private
        pure
        returns (int24 roundedTick_)
    {
        if (tickWithPenalty < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            roundedTick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tickWithPenalty)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks: we should be able to get the price for `tickWithPenalty_ - liquidationPenalty`
            while (roundedTick_ < TickMath.MIN_TICK + int24(liqPenalty)) {
                roundedTick_ += tickSpacing;
            }
        } else {
            // rounding is desirable here
            // slither-disable-next-line divide-before-multiply
            roundedTick_ = (tickWithPenalty / tickSpacing) * tickSpacing;
        }
    }
}
