// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IBaseRebalancer } from "../../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IOwnershipCallback } from "../../interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { IUsdnProtocolActions } from "../../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { Permit2TokenBitfield } from "../../libraries/Permit2TokenBitfield.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from "./UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as ActionsVault } from "./UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtils as Utils } from "./UsdnProtocolUtils.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolActionsUtilsLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using Permit2TokenBitfield for Permit2TokenBitfield.Bitfield;

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions}
    function liquidate(Types.Storage storage s, bytes calldata currentPriceData, uint16 iterations)
        public
        returns (uint256 liquidatedPositions_)
    {
        uint256 balanceBefore = address(this).balance;
        PriceInfo memory currentPrice =
            ActionsVault._getOraclePrice(s, Types.ProtocolAction.Liquidation, 0, "", currentPriceData);

        (liquidatedPositions_,) = Long._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            iterations,
            true,
            Types.ProtocolAction.Liquidation,
            currentPriceData
        );

        ActionsVault._refundExcessEther(0, 0, balanceBefore);
        ActionsVault._checkPendingFee(s);
    }

    /**
     * @notice See {IUsdnProtocolActions}
     * @dev TODO: refactor to loop on the queue and then index into `previousActionsData` when an actionable pending
     * action has been found, to avoid loop multiple times over the unactionable items in the queue
     */
    function validateActionablePendingActions(
        Types.Storage storage s,
        Types.PreviousActionsData calldata previousActionsData,
        uint256 maxValidations
    ) public returns (uint256 validatedActions_) {
        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;

        if (maxValidations > previousActionsData.rawIndices.length) {
            maxValidations = previousActionsData.rawIndices.length;
        }
        do {
            (, bool executed, bool liq, uint256 securityDepositValue) =
                ActionsVault._executePendingAction(s, previousActionsData);
            if (!executed && !liq) {
                break;
            }
            unchecked {
                validatedActions_++;
                amountToRefund += securityDepositValue;
            }
        } while (validatedActions_ < maxValidations);
        ActionsVault._refundExcessEther(0, amountToRefund, balanceBefore);
        ActionsVault._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function transferPositionOwnership(Types.Storage storage s, Types.PositionId calldata posId, address newOwner)
        public
    {
        (bytes32 tickHash, uint256 version) = Core._tickHash(s, posId.tick);
        if (posId.tickVersion != version) {
            revert IUsdnProtocolErrors.UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        Types.Position storage pos = s._longPositions[tickHash][posId.index];

        if (msg.sender != pos.user) {
            revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
        }
        if (newOwner == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }

        pos.user = newOwner;

        if (ERC165Checker.supportsInterface(newOwner, type(IOwnershipCallback).interfaceId)) {
            IOwnershipCallback(newOwner).ownershipCallback(msg.sender, posId);
        }

        emit IUsdnProtocolEvents.PositionOwnershipTransferred(posId, msg.sender, newOwner);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The close vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the close limit on the vault side, otherwise revert
     * @param s The storage of the protocol
     * @param posTotalExpoToClose The total expo to remove position
     * @param posValueToCloseAfterFees The value to remove from the position after the fees are applied
     * @param fees The fees applied to the position, going to the vault
     */
    function _checkImbalanceLimitClose(
        Types.Storage storage s,
        uint256 posTotalExpoToClose,
        uint256 posValueToCloseAfterFees,
        uint256 fees
    ) public view {
        int256 closeExpoImbalanceLimitBps;
        if (msg.sender == address(s._rebalancer)) {
            closeExpoImbalanceLimitBps = s._rebalancerCloseExpoImbalanceLimitBps;
        } else {
            closeExpoImbalanceLimitBps = s._closeExpoImbalanceLimitBps;
        }

        // early return in case limit is disabled
        if (closeExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newLongBalance = s._balanceLong.toInt256().safeSub(posValueToCloseAfterFees.toInt256());
        uint256 newTotalExpo = s._totalExpo - posTotalExpoToClose;
        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault + fees.toInt256());

        int256 imbalanceBps = Long._calcImbalanceCloseBps(currentVaultExpo, newLongBalance, newTotalExpo);

        if (imbalanceBps > closeExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Send rewards to the liquidator
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain
     * @param s The storage of the protocol
     * @param liquidatedTicks The number of ticks that were liquidated
     * @param remainingCollateral The amount of collateral remaining after liquidations
     * @param rebased Whether a USDN rebase was performed
     * @param action The protocol action that triggered liquidations
     * @param rebaseCallbackResult The rebase callback result, if any
     * @param priceData The price oracle update data
     */
    function _sendRewardsToLiquidator(
        Types.Storage storage s,
        uint16 liquidatedTicks,
        int256 remainingCollateral,
        bool rebased,
        bool rebalancerTriggered,
        Types.ProtocolAction action,
        bytes memory rebaseCallbackResult,
        bytes memory priceData
    ) public {
        // get how much we should give to the liquidator as rewards
        uint256 liquidationRewards = s._liquidationRewardsManager.getLiquidationRewards(
            liquidatedTicks, remainingCollateral, rebased, rebalancerTriggered, action, rebaseCallbackResult, priceData
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
     * @notice Prepare the pending action struct for an open position and add it to the queue
     * @param s The storage of the protocol
     * @param to The address that will be the owner of the position
     * @param validator The address that will validate the open position
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The open position action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createOpenPendingAction(
        Types.Storage storage s,
        address to,
        address validator,
        uint64 securityDepositValue,
        Types.InitiateOpenPositionData memory data
    ) public returns (uint256 amountToRefund_) {
        Types.LongPendingAction memory action = Types.LongPendingAction({
            action: Types.ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            closeLiqPenalty: 0,
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            tick: data.posId.tick,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: data.posId.tickVersion,
            index: data.posId.index,
            liqMultiplier: data.liqMultiplier,
            closeBoundedPositionValue: 0
        });
        amountToRefund_ = Core._addPendingAction(s, validator, Core._convertLongPendingAction(action));
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the open position action
     * @param s The storage of the protocol
     * @param pending The pending action data
     * @param priceData The current price data
     * @return data_ The {ValidateOpenPosition} data struct
     * @return liquidated_ Whether the position was liquidated
     */
    function _prepareValidateOpenPositionData(
        Types.Storage storage s,
        Types.PendingAction memory pending,
        bytes calldata priceData
    ) public returns (Types.ValidateOpenPositionData memory data_, bool liquidated_) {
        data_.action = Core._toLongPendingAction(pending);
        PriceInfo memory currentPrice = ActionsVault._getOraclePrice(
            s,
            Types.ProtocolAction.ValidateOpenPosition,
            data_.action.timestamp,
            _calcActionId(data_.action.validator, data_.action.timestamp),
            priceData
        );
        data_.currentPrice = (currentPrice.price).toUint128();
        // apply fees on price
        data_.startPrice =
            (currentPrice.price + currentPrice.price * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();

        (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            Types.ProtocolAction.ValidateOpenPosition,
            priceData
        );

        uint256 version;
        (data_.tickHash, version) = Core._tickHash(s, data_.action.tick);
        if (version != data_.action.tickVersion) {
            // the current tick version doesn't match the version from the pending action
            // this means the position has been liquidated in the meantime
            emit IUsdnProtocolEvents.StalePendingActionRemoved(
                data_.action.validator,
                Types.PositionId({
                    tick: data_.action.tick,
                    tickVersion: data_.action.tickVersion,
                    index: data_.action.index
                })
            );
            return (data_, true);
        }

        if (data_.isLiquidationPending) {
            return (data_, false);
        }

        // get the position
        data_.pos = s._longPositions[data_.tickHash][data_.action.index];
        // re-calculate leverage
        data_.liquidationPenalty = s._tickData[data_.tickHash].liquidationPenalty;
        data_.liqPriceWithoutPenalty =
            Long.getEffectivePriceForTick(s, Utils.calcTickWithoutPenalty(data_.action.tick, data_.liquidationPenalty));
        // reverts if liqPriceWithoutPenalty >= startPrice
        data_.leverage = _getLeverage(data_.startPrice, data_.liqPriceWithoutPenalty);
        // calculate how much the position that was opened in the initiate is now worth (it might be too large or too
        // small considering the new entry price). We will adjust the long and vault balances accordingly
        uint128 lastPrice = s._lastPrice;
        // multiplication cannot overflow because operands are uint128
        // lastPrice is larger than liqPriceWithoutPenalty because we performed liquidations above and would early
        // return in case of liquidation of this position
        data_.oldPosValue = Utils.positionValue(data_.pos.totalExpo, lastPrice, data_.liqPriceWithoutPenalty);
    }

    /**
     * @notice Perform checks for the initiate close position action
     * @dev Reverts if the to address is zero, the position was not validated yet, the position is not owned by the
     * user, the amount to close is higher than the position amount, or the amount to close is zero
     * @param s The storage of the protocol
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address of the validator
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param pos The position to close
     */
    function _checkInitiateClosePosition(
        Types.Storage storage s,
        address owner,
        address to,
        address validator,
        uint128 amountToClose,
        Types.Position memory pos
    ) public view {
        if (to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (pos.user != owner) {
            revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
        }
        if (!pos.validated) {
            revert IUsdnProtocolErrors.UsdnProtocolPositionNotValidated();
        }
        if (amountToClose == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }
        if (amountToClose > pos.amount) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        // make sure the remaining position is higher than _minLongPosition
        // for the Rebalancer, we allow users to close their position fully in every case
        uint128 remainingAmount = pos.amount - amountToClose;
        if (remainingAmount > 0 && remainingAmount < s._minLongPosition) {
            IBaseRebalancer rebalancer = s._rebalancer;
            if (owner == address(rebalancer)) {
                // note: the rebalancer always indicates the rebalancer user's address as validator
                uint128 userPosAmount = rebalancer.getUserDepositData(validator).amount;
                if (amountToClose != userPosAmount) {
                    revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
                }
            } else {
                revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
            }
        }
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate close position action
     * @dev Reverts if the imbalance limit is reached, or if any of the checks in `_checkInitiateClosePosition` fail
     * Returns without creating a pending action if the position gets liquidated in this transaction
     * @param s The storage of the protocol
     * @param params The parameters for the _prepareClosePositionData function
     * @return data_ The close position data
     * @return liquidated_ Whether the position was liquidated and the caller should return early
     */
    function _prepareClosePositionData(
        Types.Storage storage s,
        Types.PrepareInitiateClosePositionParams calldata params
    ) public returns (Types.ClosePositionData memory data_, bool liquidated_) {
        (data_.pos, data_.liquidationPenalty) = ActionsLong.getLongPosition(s, params.posId);

        _checkInitiateClosePosition(s, params.owner, params.to, params.validator, params.amountToClose, data_.pos);

        {
            PriceInfo memory currentPrice = ActionsVault._getOraclePrice(
                s,
                Types.ProtocolAction.InitiateClosePosition,
                block.timestamp,
                _calcActionId(params.owner, uint128(block.timestamp)),
                params.currentPriceData
            );
            if (currentPrice.price < params.userMinPrice) {
                revert IUsdnProtocolErrors.UsdnProtocolSlippageMinPriceExceeded();
            }

            (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
                s,
                currentPrice.neutralPrice,
                currentPrice.timestamp,
                s._liquidationIteration,
                false,
                Types.ProtocolAction.InitiateClosePosition,
                params.currentPriceData
            );

            uint256 version = s._tickVersion[params.posId.tick];
            if (version != params.posId.tickVersion) {
                // the current tick version doesn't match the version from the position,
                // that means that the position has been liquidated in this transaction
                return (data_, true);
            }
        }

        if (data_.isLiquidationPending) {
            return (data_, false);
        }

        data_.totalExpoToClose = (uint256(data_.pos.totalExpo) * params.amountToClose / data_.pos.amount).toUint128();

        data_.longTradingExpo = s._totalExpo - s._balanceLong;
        data_.liqMulAcc = s._liqMultiplierAccumulator;
        data_.lastPrice = s._lastPrice;

        // the approximate value position to remove is calculated with `_lastPrice`, so not taking into account
        // any fees. This way, the removal of the position doesn't affect the liquidation multiplier calculations

        // to have maximum precision, we do not pre-compute the liquidation multiplier with a fixed
        // precision just now, we will store it in the pending action later, to be used in the validate action
        int24 tick = Utils.calcTickWithoutPenalty(params.posId.tick, data_.liquidationPenalty);
        uint128 liqPriceWithoutPenalty =
            Long.getEffectivePriceForTick(tick, data_.lastPrice, data_.longTradingExpo, data_.liqMulAcc);

        uint256 balanceLong = s._balanceLong;

        data_.tempPositionValue =
            _assetToRemove(balanceLong, data_.lastPrice, liqPriceWithoutPenalty, data_.totalExpoToClose);

        uint128 priceAfterFees =
            (data_.lastPrice - data_.lastPrice * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();

        uint256 posValueAfterFees =
            _assetToRemove(balanceLong, priceAfterFees, liqPriceWithoutPenalty, data_.totalExpoToClose);

        // we perform the imbalance check with the position value after fees
        // the position value after fees is smaller than the position value before fees so the subtraction is safe
        _checkImbalanceLimitClose(
            s, data_.totalExpoToClose, posValueAfterFees, data_.tempPositionValue - posValueAfterFees
        );
    }

    /**
     * @notice Prepare the pending action struct for the close position action and add it to the queue
     * @param s The storage of the protocol
     * @param to The address that will receive the assets
     * @param validator The validator for the pending action
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The close position data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createClosePendingAction(
        Types.Storage storage s,
        address to,
        address validator,
        Types.PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        Types.ClosePositionData memory data
    ) public returns (uint256 amountToRefund_) {
        Types.LongPendingAction memory action = Types.LongPendingAction({
            action: Types.ProtocolAction.ValidateClosePosition,
            timestamp: uint40(block.timestamp),
            closeLiqPenalty: data.liquidationPenalty,
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            tick: posId.tick,
            closeAmount: amountToClose,
            closePosTotalExpo: data.totalExpoToClose,
            tickVersion: posId.tickVersion,
            index: posId.index,
            liqMultiplier: Long._calcFixedPrecisionMultiplier(data.lastPrice, data.longTradingExpo, data.liqMulAcc),
            closeBoundedPositionValue: data.tempPositionValue
        });
        amountToRefund_ = Core._addPendingAction(s, validator, Core._convertLongPendingAction(action));
    }

    /**
     * @notice Calculate how much wstETH must be removed from the long balance due to a position closing
     * @dev The amount is bound by the amount of wstETH available on the long side
     * @param balanceLong The balance of long positions (with asset decimals)
     * @param price The price to use for the position value calculation
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @param posExpo The total expo of the position
     * @return boundedPosValue_ The amount of assets to remove from the long balance, bound by zero and the available
     * long balance
     */
    function _assetToRemove(uint256 balanceLong, uint128 price, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        public
        pure
        returns (uint256 boundedPosValue_)
    {
        // calculate position value
        int256 positionValue = Long._positionValue(price, liqPriceWithoutPenalty, posExpo);

        if (positionValue <= 0) {
            // should not happen, unless we did not manage to liquidate all ticks that needed to be liquidated during
            // the initiateClosePosition
            boundedPosValue_ = 0;
        } else if (uint256(positionValue) > balanceLong) {
            boundedPosValue_ = balanceLong;
        } else {
            boundedPosValue_ = uint256(positionValue);
        }
    }

    /**
     * @notice Remove the provided total amount from its position and update the tick data and position
     * @dev Note: this method does not update the long balance
     * If the amount to remove is greater than or equal to the position's total amount, the position is deleted instead
     * @param s The storage of the protocol
     * @param tick The tick to remove from
     * @param index Index of the position in the tick array
     * @param pos The position to remove the amount from
     * @param amountToRemove The amount to remove from the position
     * @param totalExpoToRemove The total expo to remove from the position
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _removeAmountFromPosition(
        Types.Storage storage s,
        int24 tick,
        uint256 index,
        Types.Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) public returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        (bytes32 tickHash,) = Core._tickHash(s, tick);
        Types.TickData storage tickData = s._tickData[tickHash];
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(Utils.calcTickWithoutPenalty(tick, tickData.liquidationPenalty));
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
                s._tickBitmap.unset(Core._calcBitmapIndexFromTick(s, tick));
            }
        }

        s._totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
        liqMultiplierAccumulator_ =
            s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * totalExpoToRemove));
        s._liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /**
     * @notice Save a new position in the protocol, adjusting the tick data and global variables
     * @dev Note: this method does not update the long balance
     * @param s The storage of the protocol
     * @param tick The tick to hold the new position
     * @param long The position to save
     * @param liquidationPenalty The liquidation penalty for the tick
     * @return tickVersion_ The version of the tick
     * @return index_ The index of the position in the tick array
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _saveNewPosition(
        Types.Storage storage s,
        int24 tick,
        Types.Position memory long,
        uint24 liquidationPenalty
    ) public returns (uint256 tickVersion_, uint256 index_, HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        bytes32 tickHash;
        (tickHash, tickVersion_) = Core._tickHash(s, tick);

        // add to tick array
        Types.Position[] storage tickArray = s._longPositions[tickHash];
        index_ = tickArray.length;
        if (tick > s._highestPopulatedTick) {
            // keep track of the highest populated tick
            s._highestPopulatedTick = tick;

            emit IUsdnProtocolEvents.HighestPopulatedTickUpdated(tick);
        }
        tickArray.push(long);

        // adjust state
        s._totalExpo += long.totalExpo;
        ++s._totalLongPositions;

        // update tick data
        Types.TickData storage tickData = s._tickData[tickHash];
        // the unadjusted tick price for the accumulator might be different depending
        // if we already have positions in the tick or not
        uint256 unadjustedTickPrice;
        if (tickData.totalPos == 0) {
            // first position in this tick, we need to reflect that it is populated
            s._tickBitmap.set(Core._calcBitmapIndexFromTick(s, tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
            unadjustedTickPrice = TickMath.getPriceAtTick(Utils.calcTickWithoutPenalty(tick, liquidationPenalty));
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's `liquidationPenalty` since it remains constant
            unadjustedTickPrice =
                TickMath.getPriceAtTick(Utils.calcTickWithoutPenalty(tick, tickData.liquidationPenalty));
        }
        // update the accumulator with the correct tick price (depending on the liquidation penalty value)
        liqMultiplierAccumulator_ = s._liqMultiplierAccumulator.add(HugeUint.wrap(unadjustedTickPrice * long.totalExpo));
        s._liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /**
     * @notice Calculate a unique identifier for a pending action, that can be used by the oracle middleware to link
     * a `Initiate` call with the corresponding `Validate` call
     * @param validator The address of the validator
     * @param initiateTimestamp The timestamp of the initiate action
     * @return actionId_ The unique action ID
     */
    function _calcActionId(address validator, uint128 initiateTimestamp) public pure returns (bytes32 actionId_) {
        actionId_ = keccak256(abi.encodePacked(validator, initiateTimestamp));
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
}
