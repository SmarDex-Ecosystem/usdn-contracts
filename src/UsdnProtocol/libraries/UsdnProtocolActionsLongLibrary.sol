// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IPaymentCallback } from "../../interfaces/UsdnProtocol/IPaymentCallback.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Accumulator, HugeUint } from "../../libraries/Accumulator.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";
import { console2 } from "forge-std/Test.sol";

library UsdnProtocolActionsLongLibrary {
    using Accumulator for HugeUint.Uint512;
    using SafeCast for uint256;
    using SafeTransferLib for address;

    /**
     * @dev Data structure for the {_validateClosePositionWithAction} function.
     * @param isLiquidationPending Whether a liquidation is pending.
     * @param priceWithFees The price of the position with fees.
     * @param liquidationPrice The liquidation price of the position.
     * @param positionValue The value of the position. The amount the user will receive when closing the position.
     */
    struct ValidateClosePositionWithActionData {
        bool isLiquidationPending;
        uint128 priceWithFees;
        uint128 liquidationPrice;
        int256 positionValue;
    }

    /**
     * @dev Data structure for the {_validateOpenPositionWithAction} function.
     * @param currentLiqPenalty The current liquidation penalty parameter value.
     * @param newPosId The new position id.
     * @param liquidationPenalty The liquidation penalty of the tick we are considering.
     */
    struct MaxLeverageData {
        uint24 currentLiqPenalty;
        Types.PositionId newPosId;
        uint24 liquidationPenalty;
    }

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions.initiateOpenPosition}.
    function initiateOpenPosition(
        Types.InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) external returns (bool isInitiated_, Types.PositionId memory posId_) {
        Types.Storage storage s = Utils._getMainStorage();

        if (params.deadline < block.timestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolDeadlineExceeded();
        }
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        params.securityDepositValue = securityDepositValue;
        uint256 validatorAmount;
        (posId_, validatorAmount, isInitiated_) = _initiateOpenPosition(params, currentPriceData);

        uint256 amountToRefund;
        if (isInitiated_) {
            unchecked {
                amountToRefund += Vault._executePendingActionOrRevert(previousActionsData);
            }
        }

        // refund any securityDeposit from a stale pending action to the validator
        if (validatorAmount > 0) {
            if (params.validator != msg.sender) {
                balanceBefore -= validatorAmount;
                Utils._refundEther(validatorAmount, payable(params.validator));
            } else {
                amountToRefund += validatorAmount;
            }
        }

        Utils._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions.validateOpenPosition}.
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) external returns (Types.LongActionOutcome outcome_, Types.PositionId memory posId_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool isValidated;
        bool isLiquidated;
        (amountToRefund, isValidated, isLiquidated, posId_) = _validateOpenPosition(validator, openPriceData);
        uint256 securityDeposit;
        if (isValidated || isLiquidated) {
            securityDeposit = Vault._executePendingActionOrRevert(previousActionsData);
        }

        if (isLiquidated) {
            outcome_ = Types.LongActionOutcome.Liquidated;
        } else if (!isValidated) {
            outcome_ = Types.LongActionOutcome.PendingLiquidations;
        }

        if (msg.sender != validator) {
            Utils._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = securityDeposit;
        } else {
            amountToRefund += securityDeposit;
        }
        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions.initiateClosePosition}.
    function initiateClosePosition(
        Types.InitiateClosePositionParams memory params,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData,
        bytes calldata delegationSignature
    ) external returns (Types.LongActionOutcome outcome_) {
        if (params.deadline < block.timestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolDeadlineExceeded();
        }
        if (msg.value < params.securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        (uint256 validatorAmount, bool isInitiated, bool isLiquidated) =
            _initiateClosePosition(params, currentPriceData, delegationSignature);

        uint256 amountToRefund;
        if (isInitiated || isLiquidated) {
            unchecked {
                amountToRefund += Vault._executePendingActionOrRevert(previousActionsData);
            }
        }

        if (isLiquidated) {
            outcome_ = Types.LongActionOutcome.Liquidated;
        } else if (!isInitiated) {
            outcome_ = Types.LongActionOutcome.PendingLiquidations;
        }

        // refund any securityDeposit from a stale pending action to the validator
        if (validatorAmount > 0) {
            if (params.validator != msg.sender) {
                balanceBefore -= validatorAmount;
                Utils._refundEther(validatorAmount, payable(params.validator));
            } else {
                amountToRefund += validatorAmount;
            }
        }

        Utils._refundExcessEther(params.securityDepositValue, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions.validateClosePosition}.
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) external returns (Types.LongActionOutcome outcome_) {
        uint256 balanceBefore = address(this).balance;

        (uint256 amountToRefund, bool isValidated, bool isLiquidated) =
            _validateClosePosition(validator, closePriceData);
        uint256 securityDeposit;
        if (isValidated || isLiquidated) {
            securityDeposit = Vault._executePendingActionOrRevert(previousActionsData);
        }

        if (isLiquidated) {
            outcome_ = Types.LongActionOutcome.Liquidated;
        } else if (!isValidated) {
            outcome_ = Types.LongActionOutcome.PendingLiquidations;
        }

        if (msg.sender != validator) {
            Utils._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = securityDeposit;
        } else {
            amountToRefund += securityDeposit;
        }
        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     *
     * @notice Validates an open position action.
     * @param pending The pending action's data.
     * @param priceData The current price data.
     * @return isValidated_ Whether the action is validated.
     * @return isLiquidated_ Whether the pending action is liquidated.
     * @return posId_ The (potentially updated) position ID, or `NO_POSITION_TICK` in the `tick` field if the position
     * was liquidated.
     */
    function _validateOpenPositionWithAction(Types.PendingAction memory pending, bytes calldata priceData)
        public
        returns (bool isValidated_, bool isLiquidated_, Types.PositionId memory posId_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        (Types.ValidateOpenPositionData memory data, bool liquidated) =
            _prepareValidateOpenPositionData(pending, priceData);
        console2.log("liquidated", liquidated);
        console2.log("data.isLiquidationPending", data.isLiquidationPending);

        if (liquidated) {
            posId_.tick = Constants.NO_POSITION_TICK;
            return (false, true, posId_);
        }

        posId_ =
            Types.PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index });
        if (data.isLiquidationPending) {
            return (false, false, posId_);
        }

        // leverage is always greater than one (`liquidationPrice` is positive)
        // even if it drops below _minLeverage between the initiate and validate actions, we still allow it
        // however, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        uint128 maxLeverage = uint128(s._maxLeverage);

        console2.log("data.leverage", data.leverage);
        console2.log("maxLeverage", maxLeverage);
        console2.log("data.leverage > maxLeverage", data.leverage > maxLeverage);

        if (data.leverage > maxLeverage) {
            MaxLeverageData memory maxLeverageData;
            // theoretical liquidation price for _maxLeverage
            data.liqPriceWithoutPenalty = Utils._getLiquidationPrice(data.startPrice, maxLeverage);
            // find corresponding tick and actual liq price with current penalty setting
            maxLeverageData.currentLiqPenalty = s._liquidationPenalty;
            (maxLeverageData.newPosId.tick, data.liqPriceWithoutPenaltyNorFunding) = Long._getTickFromDesiredLiqPrice(
                data.liqPriceWithoutPenalty,
                data.action.liqMultiplier,
                s._tickSpacing,
                maxLeverageData.currentLiqPenalty
            );

            // retrieve the actual penalty for this tick we want to use
            maxLeverageData.liquidationPenalty = Long.getTickLiquidationPenalty(maxLeverageData.newPosId.tick);
            // check if the penalty for that tick is different from the current setting
            // if the penalty is the same, then `data.liqPriceWithoutPenaltyNorFunding` is already correct
            if (maxLeverageData.liquidationPenalty != maxLeverageData.currentLiqPenalty) {
                // the tick's imposed penalty is different from the current setting, so the
                // `liqPriceWithoutPenaltyNorFunding` we got above can't be used to calculate the leverage
                // we must instead use the tick's penalty to find the new `liqPriceWithoutPenaltyNorFunding` and
                // calculate the total exposure

                // note: In case the tick liquidation penalty is lower than the current setting, it might lead to a
                // leverage that exceeds the max leverage slightly. We allow this behavior in this rare occurrence

                // retrieve exact liquidation price without penalty
                // we consider the liquidation multiplier as it was during the initiation, to ignore any funding
                // that was due between the initiation and the validation
                data.liqPriceWithoutPenaltyNorFunding = Utils._getEffectivePriceForTick(
                    Utils._calcTickWithoutPenalty(maxLeverageData.newPosId.tick, maxLeverageData.liquidationPenalty),
                    data.action.liqMultiplier
                );
            }

            // recalculate the liquidation price of the tick
            data.liqPriceWithoutPenalty = Utils._getEffectivePriceForTick(
                Utils._calcTickWithoutPenalty(maxLeverageData.newPosId.tick, maxLeverageData.liquidationPenalty)
            );
            // must calculate before removing the position from the tick which affects the trading expo
            uint128 liqPriceWithPenalty = Utils._getEffectivePriceForTick(maxLeverageData.newPosId.tick);

            // move the position to its new tick, update its total exposure, and return the new tickVersion and index
            // remove position from old tick completely
            Long._removeAmountFromPosition(
                data.action.tick, data.action.index, data.pos, data.pos.amount, data.pos.totalExpo
            );

            console2.log("data.lastPrice", data.lastPrice);
            console2.log("liqPriceWithPenalty", liqPriceWithPenalty);
            console2.log("data.lastPrice <= liqPriceWithPenalty", data.lastPrice <= liqPriceWithPenalty);

            // if the last price is below the liquidation price with penalty of the new position, the position is
            // already underwater and we might be unable to calculate the new position value if we are further below
            // `liqPriceWithoutPenalty`
            // this is extremely unlikely, but we have no other choice but to liquidate it it if happens
            if (data.lastPrice <= liqPriceWithPenalty) {
                s._balanceLong -= data.oldPosValue;
                s._balanceVault += data.oldPosValue;
                // position was already removed from the tick above

                emit IUsdnProtocolEvents.LiquidatedPosition(
                    data.action.validator,
                    Types.PositionId({
                        tick: data.action.tick,
                        tickVersion: data.action.tickVersion,
                        index: data.action.index
                    }),
                    data.lastPrice,
                    liqPriceWithPenalty
                );
                return (false, true, Types.PositionId({ tick: Constants.NO_POSITION_TICK, tickVersion: 0, index: 0 }));
            }

            // update position total exposure (because of new leverage / liq price)
            data.pos.totalExpo =
                Utils._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenaltyNorFunding);
            // mark the position as validated
            data.pos.validated = true;
            // insert position into new tick
            (maxLeverageData.newPosId.tickVersion, maxLeverageData.newPosId.index,) =
                Core._saveNewPosition(maxLeverageData.newPosId.tick, data.pos, maxLeverageData.liquidationPenalty);

            // adjust the balances to reflect the new value of the position
            uint256 updatedPosValue =
                Utils._positionValueOptimized(data.pos.totalExpo, data.lastPrice, data.liqPriceWithoutPenalty);
            _validateOpenPositionUpdateBalances(updatedPosValue, data.oldPosValue);

            emit IUsdnProtocolEvents.LiquidationPriceUpdated(
                Types.PositionId({
                    tick: data.action.tick,
                    tickVersion: data.action.tickVersion,
                    index: data.action.index
                }),
                maxLeverageData.newPosId
            );
            emit IUsdnProtocolEvents.ValidatedOpenPosition(
                data.action.to, data.action.validator, data.pos.totalExpo, data.startPrice, maxLeverageData.newPosId
            );

            return (true, false, maxLeverageData.newPosId);
        }

        // calculate the new total exposure
        uint128 expoBefore = data.pos.totalExpo;
        uint128 expoAfter =
            Utils._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenaltyNorFunding);

        // update the total exposure of the position
        data.pos.totalExpo = expoAfter;
        // mark the position as validated
        data.pos.validated = true;
        // SSTORE
        s._longPositions[data.tickHash][data.action.index] = data.pos;
        // update the total exposure by adding the position's new exposure and removing the old one
        // do not use += or it will underflow
        s._totalExpo = s._totalExpo + expoAfter - expoBefore;

        // update the tick data and the liqMultiplierAccumulator
        {
            Types.TickData storage tickData = s._tickData[data.tickHash];
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(Utils._calcTickWithoutPenalty(data.action.tick, data.liquidationPenalty));
            tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
            s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.add(
                HugeUint.wrap(expoAfter * unadjustedTickPrice)
            ).sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
        }

        // adjust the balances to reflect the new value of the position
        uint256 newPosValue = Utils._positionValueOptimized(expoAfter, data.lastPrice, data.liqPriceWithoutPenalty);
        _validateOpenPositionUpdateBalances(newPosValue, data.oldPosValue);

        isValidated_ = true;
        emit IUsdnProtocolEvents.ValidatedOpenPosition(
            data.action.to, data.action.validator, expoAfter, data.startPrice, posId_
        );
    }

    /**
     * @notice Initiates an open position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the {IUsdnProtocolTypes.ProtocolAction}'s `InitiateOpenPosition` action.
     * The price validation might require payment according to the return value of the
     * {IBaseOracleMiddleware.validationCost} function of the middleware.
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data.
     * @param params The parameters for the open position initiation.
     * @param currentPriceData The current price data.
     * @return posId_ The unique index of the opened position.
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action.
     * @return isInitiated_ Whether the action is initiated.
     */
    function _initiateOpenPosition(Types.InitiateOpenPositionParams memory params, bytes calldata currentPriceData)
        internal
        returns (Types.PositionId memory posId_, uint256 amountToRefund_, bool isInitiated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (params.to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (params.validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (params.amount == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }
        if (params.amount < s._minLongPosition) {
            revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
        }

        Types.InitiateOpenPositionData memory data = Long._prepareInitiateOpenPositionData(
            Types.PrepareInitiateOpenPositionParams({
                validator: params.validator,
                amount: params.amount,
                desiredLiqPrice: params.desiredLiqPrice,
                userMaxPrice: params.userMaxPrice,
                userMaxLeverage: params.userMaxLeverage,
                currentPriceData: currentPriceData
            })
        );

        if (data.isLiquidationPending) {
            // value to indicate the position was not created
            posId_.tick = Constants.NO_POSITION_TICK;
            return (posId_, params.securityDepositValue, false);
        }

        // register position and adjust contract state
        Types.Position memory long = Types.Position({
            validated: false,
            user: params.to,
            amount: params.amount,
            totalExpo: data.positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });
        (data.posId.tickVersion, data.posId.index,) =
            Core._saveNewPosition(data.posId.tick, long, data.liquidationPenalty);
        // because of the position fee, the position value is smaller than the amount
        s._balanceLong += data.positionValue;
        // positionValue must be smaller than or equal to amount, because the adjustedPrice (with fee) is larger than
        // or equal to the current price
        s._balanceVault += long.amount - data.positionValue;
        posId_ = data.posId;

        amountToRefund_ = Core._createOpenPendingAction(params.to, params.validator, params.securityDepositValue, data);

        if (ERC165Checker.supportsInterface(msg.sender, type(IPaymentCallback).interfaceId)) {
            Utils._transferCallback(s._asset, params.amount, address(this));
        } else {
            // slither-disable-next-line arbitrary-send-erc20
            address(s._asset).safeTransferFrom(params.user, address(this), params.amount);
        }

        isInitiated_ = true;
        emit IUsdnProtocolEvents.InitiatedOpenPosition(
            params.to,
            params.validator,
            uint40(block.timestamp),
            data.positionTotalExpo,
            params.amount,
            data.adjustedPrice,
            posId_
        );
    }

    /**
     * @notice Retrieves the pending action data of the owner, try to validate it and clear it if successful.
     * @param validator The address of the validator.
     * @param priceData The price data for the pending action to validate.
     * @return securityDepositValue_ The value of the security deposit to refund.
     * @return isValidated_ Whether the action is validated.
     * @return isLiquidated_ Whether the pending action is liquidated.
     * @return posId_ The (potentially updated) position ID, or `NO_POSITION_TICK` in the `tick` field if the position
     * was liquidated.
     */
    function _validateOpenPosition(address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_, bool isLiquidated_, Types.PositionId memory posId_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateOpenPosition) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        (isValidated_, isLiquidated_, posId_) = _validateOpenPositionWithAction(pending, priceData);

        if (isValidated_ || isLiquidated_) {
            Utils._clearPendingAction(validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
    }

    /**
     * @notice Updates the protocol balances during {validateOpenPosition} to reflect the new entry price of the
     * position.
     * @dev We need to adjust the balances because the position that was created during the {initiateOpenPosition} might
     * have gained or lost some value, and we need to reflect that the position value is now `newPosValue`.
     * Any potential PnL on that temporary position must be "cancelled" so that it doesn't affect the other positions
     * and the vault.
     * @param newPosValue The new value of the position.
     * @param oldPosValue The value of the position at the current price, using its old parameters.
     */
    function _validateOpenPositionUpdateBalances(uint256 newPosValue, uint256 oldPosValue) internal {
        Types.Storage storage s = Utils._getMainStorage();

        if (newPosValue > oldPosValue) {
            // the long side is missing some value, we need to take it from the vault
            uint256 diff;
            unchecked {
                diff = newPosValue - oldPosValue;
                uint256 balanceVault = s._balanceVault;
                if (diff > balanceVault) {
                    diff = balanceVault;
                }
                s._balanceVault = balanceVault - diff;
            }
            s._balanceLong += diff;
        } else if (newPosValue < oldPosValue) {
            // the long side has too much value, we need to give it to the vault side
            uint256 diff;
            unchecked {
                diff = oldPosValue - newPosValue;
                uint256 balanceLong = s._balanceLong;
                if (diff > balanceLong) {
                    diff = balanceLong;
                }
                s._balanceLong = balanceLong - diff;
            }
            s._balanceVault += diff;
        }
        // if both are equal, no action is needed
    }

    /**
     * @notice Updates protocol balances, liquidate positions if necessary, then validate the open position action.
     * @param pending The pending action data.
     * @param priceData The price data for the pending action.
     * @return data_ The {IUsdnProtocolTypes.ValidateOpenPositionData} data structure.
     * @return isLiquidated_ Whether the position is liquidated.
     */
    function _prepareValidateOpenPositionData(Types.PendingAction memory pending, bytes calldata priceData)
        internal
        returns (Types.ValidateOpenPositionData memory data_, bool isLiquidated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        data_.action = Utils._toLongPendingAction(pending);
        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.ValidateOpenPosition,
            data_.action.timestamp,
            Utils._calcActionId(data_.action.validator, data_.action.timestamp),
            priceData
        );
        // apply fees on price
        data_.startPrice =
            (currentPrice.price + currentPrice.price * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();

        (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            Types.ProtocolAction.ValidateOpenPosition,
            priceData
        );

        uint256 version;
        (data_.tickHash, version) = Utils._tickHash(data_.action.tick);
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

        data_.lastPrice = s._lastPrice;
        uint128 liqPriceWithPenalty = Utils._getEffectivePriceForTick(data_.action.tick);
        // a user that triggers this condition will be stuck in a validation loop until it liquidates its own position
        // with the stored `_lastPrice`
        if (data_.lastPrice <= liqPriceWithPenalty) {
            data_.isLiquidationPending = true;
            return (data_, false);
        }

        // get the position
        data_.pos = s._longPositions[data_.tickHash][data_.action.index];
        // re-calculate leverage
        data_.liquidationPenalty = s._tickData[data_.tickHash].liquidationPenalty;
        data_.liqPriceWithoutPenalty =
            Utils._getEffectivePriceForTick(Utils._calcTickWithoutPenalty(data_.action.tick, data_.liquidationPenalty));

        // calculate how much the position that was opened in the initiate is now worth (it might be too large or too
        // small considering the new leverage and lastPrice). We will adjust the long and vault balances accordingly
        // lastPrice is larger than or equal to liqPriceWithoutPenalty so the calc below does not underflow
        data_.oldPosValue =
            Utils._positionValueOptimized(data_.pos.totalExpo, data_.lastPrice, data_.liqPriceWithoutPenalty);

        data_.liqPriceWithoutPenaltyNorFunding = Utils._getEffectivePriceForTick(
            Utils._calcTickWithoutPenalty(data_.action.tick, data_.liquidationPenalty), data_.action.liqMultiplier
        );

        // if lastPrice > liqPriceWithPenalty
        // but startPrice <= liqPriceWithPenalty OR startPrice <= liqPriceWithoutPenaltyNorFunding,
        // then the user dodged liquidations. We still can't let the position open, because we can't calculate the
        // leverage with a start price that is lower than a liquidation price, and we also can't liquidate the whole
        // tick because other users could have opened positions in this tick after the user of the current position,
        // our only choice is to liquidate this position only
        if (data_.startPrice <= liqPriceWithPenalty || data_.startPrice <= data_.liqPriceWithoutPenaltyNorFunding) {
            uint256 liquidationPrice = liqPriceWithPenalty;
            // if the liquidation occurs because of liqPriceWithoutPenaltyNorFunding, use it as the effective price for
            // the liquidation event
            if (data_.startPrice > liqPriceWithPenalty && data_.startPrice <= data_.liqPriceWithoutPenaltyNorFunding) {
                liquidationPrice = data_.liqPriceWithoutPenaltyNorFunding;
            }

            s._balanceLong -= data_.oldPosValue;
            s._balanceVault += data_.oldPosValue;

            Long._removeAmountFromPosition(
                data_.action.tick, data_.action.index, data_.pos, data_.pos.amount, data_.pos.totalExpo
            );

            emit IUsdnProtocolEvents.LiquidatedPosition(
                data_.action.validator,
                Types.PositionId({
                    tick: data_.action.tick,
                    tickVersion: data_.action.tickVersion,
                    index: data_.action.index
                }),
                data_.startPrice,
                liquidationPrice
            );

            return (data_, true);
        }

        // calculate the leverage of the position without considering the penalty nor the funding by using the
        // multiplier state at T+24
        data_.leverage = Utils._getLeverage(data_.startPrice, data_.liqPriceWithoutPenaltyNorFunding);
    }

    /**
     * @notice Initiates a close position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the {IUsdnProtocolTypes.ProtocolAction}'s `InitiateClosePosition` action.
     * The price validation might require payment according to the return value of the
     * {IBaseOracleMiddleware.validationCost} function of the middleware.
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and this function will return 0.
     * The position is taken out of the tick and put in a pending state during this operation. Thus, calculations don't
     * consider this position anymore. The exit price (and thus profit) is not yet set definitively and will be done
     * during the `validate` action.
     * @param params The parameters for the close position initiation.
     * @param currentPriceData The current price data.
     * @param delegationSignature An EIP712 signature that proves the caller is authorized by the owner of the position
     * to close it on their behalf.
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action.
     * @return isInitiated_ Whether the action is initiated.
     * @return isLiquidated_ Whether the position got liquidated by this call.
     */
    function _initiateClosePosition(
        Types.InitiateClosePositionParams memory params,
        bytes calldata currentPriceData,
        bytes calldata delegationSignature
    ) internal returns (uint256 amountToRefund_, bool isInitiated_, bool isLiquidated_) {
        Types.Storage storage s = Utils._getMainStorage();

        Types.ClosePositionData memory data;
        (data, isLiquidated_) = ActionsUtils._prepareClosePositionData(
            Types.PrepareInitiateClosePositionParams({
                to: params.to,
                validator: params.validator,
                posId: params.posId,
                amountToClose: params.amountToClose,
                userMinPrice: params.userMinPrice,
                deadline: params.deadline,
                currentPriceData: currentPriceData,
                delegationSignature: delegationSignature,
                domainSeparatorV4: params.domainSeparatorV4
            })
        );

        if (isLiquidated_ || data.isLiquidationPending) {
            // position was liquidated in this transaction or liquidations are pending
            return (params.securityDepositValue, false, isLiquidated_);
        }

        amountToRefund_ = _createClosePendingAction(
            params.to, params.validator, params.posId, params.amountToClose, params.securityDepositValue, data
        );

        s._balanceLong -= data.tempPositionValue;

        Long._removeAmountFromPosition(
            params.posId.tick, params.posId.index, data.pos, params.amountToClose, data.totalExpoToClose
        );

        isInitiated_ = true;
        emit IUsdnProtocolEvents.InitiatedClosePosition(
            data.pos.user,
            params.validator,
            params.to,
            params.posId,
            data.pos.amount,
            params.amountToClose,
            data.pos.totalExpo - data.totalExpoToClose
        );
    }

    /**
     * @notice Retrieves the pending action data of the validator, try to validate it and clear it if successful.
     * @param validator The validator of the pending action.
     * @param priceData The price data for the validator's pending action.
     * @return securityDepositValue_ The value of the security deposit of the pending action.
     * @return isValidated_ Whether the action is validated.
     * @return isLiquidated_ Whether the pending action is liquidated.
     */
    function _validateClosePosition(address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_, bool isLiquidated_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateClosePosition) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        (isValidated_, isLiquidated_) = _validateClosePositionWithAction(pending, priceData);

        if (isValidated_ || isLiquidated_) {
            Utils._clearPendingAction(validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
    }

    /**
     * @notice Prepares the pending action struct for the close position action and add it to the queue.
     * @param to The address that will receive the assets.
     * @param validator The validator for the pending action.
     * @param posId The unique identifier of the position.
     * @param amountToClose The amount of collateral to remove from the position's amount.
     * @param securityDepositValue The value of the security deposit for the newly created pending action.
     * @param data The close position data.
     * @return amountToRefund_ The security deposit value of a stale pending action.
     */
    function _createClosePendingAction(
        address to,
        address validator,
        Types.PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        Types.ClosePositionData memory data
    ) internal returns (uint256 amountToRefund_) {
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
            liqMultiplier: Utils._calcFixedPrecisionMultiplier(data.lastPrice, data.longTradingExpo, data.liqMulAcc),
            closeBoundedPositionValue: data.tempPositionValue
        });
        amountToRefund_ = Core._addPendingAction(validator, Utils._convertLongPendingAction(action));
    }

    /**
     * @notice Updates protocol balances, liquidate positions if necessary, then validate the close position action.
     * @param pending The pending action data.
     * @param priceData The price data for the action to validate.
     * @return isValidated_ Whether the action is validated.
     * @return isLiquidated_ Whether the pending action is liquidated.
     */
    function _validateClosePositionWithAction(Types.PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isValidated_, bool isLiquidated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        ValidateClosePositionWithActionData memory data;
        Types.LongPendingAction memory long = Utils._toLongPendingAction(pending);

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.ValidateClosePosition,
            long.timestamp,
            Utils._calcActionId(long.validator, long.timestamp),
            priceData
        );

        (, data.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            Types.ProtocolAction.ValidateClosePosition,
            priceData
        );

        // apply fees on price
        data.priceWithFees =
            (currentPrice.price - currentPrice.price * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();

        // get liquidation price (with liq penalty) to check if the position was valid at `timestamp + validationDelay`
        data.liquidationPrice = Utils._getEffectivePriceForTick(long.tick, long.liqMultiplier);

        if (currentPrice.neutralPrice <= data.liquidationPrice) {
            // position should be liquidated, we don't transfer assets to the user
            // position was already removed from tick so no additional bookkeeping is necessary
            // credit the full amount to the vault to preserve the total balance invariant
            s._balanceVault += long.closeBoundedPositionValue;
            emit IUsdnProtocolEvents.LiquidatedPosition(
                long.validator, // not necessarily the position owner
                Types.PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
                currentPrice.neutralPrice,
                data.liquidationPrice
            );
            return (false, true);
        }

        if (data.isLiquidationPending) {
            return (false, false);
        }

        int24 tickWithoutPenalty = Utils._calcTickWithoutPenalty(long.tick, long.closeLiqPenalty);
        data.positionValue = Utils._positionValue(
            long.closePosTotalExpo,
            data.priceWithFees,
            Utils._getEffectivePriceForTick(tickWithoutPenalty, long.liqMultiplier)
        );

        uint256 assetToTransfer;
        if (data.positionValue > 0) {
            assetToTransfer = uint256(data.positionValue);
            // normally, the position value should be smaller than `long.closeBoundedPositionValue`
            // (due to the position fee)
            // we can send the difference (any remaining collateral) to the vault
            // if the price increased since the initiation, it's possible that the position value is higher than the
            // `long.closeBoundedPositionValue`. In that case, we need to take the missing assets from the vault
            if (assetToTransfer < long.closeBoundedPositionValue) {
                uint256 remainingCollateral;
                unchecked {
                    // since assetToTransfer is strictly smaller than closeBoundedPositionValue,
                    // this operation can't underflow
                    remainingCollateral = long.closeBoundedPositionValue - assetToTransfer;
                }
                s._balanceVault += remainingCollateral;
            } else if (assetToTransfer > long.closeBoundedPositionValue) {
                uint256 missingValue;
                unchecked {
                    // since assetToTransfer is strictly larger than closeBoundedPositionValue,
                    // this operation can't underflow
                    missingValue = assetToTransfer - long.closeBoundedPositionValue;
                }
                uint256 balanceVault = s._balanceVault;
                // if the vault does not have enough balance left to pay out the missing value, we take what we can
                if (missingValue > balanceVault) {
                    s._balanceVault = 0;
                    unchecked {
                        // since `missingValue` is strictly larger than `balanceVault`,
                        // their subtraction can't underflow
                        // moreover, since (missingValue - balanceVault) is smaller than or equal to `missingValue`,
                        // and since `missingValue` is smaller than or equal to `assetToTransfer`,
                        // (missingValue - balanceVault) is smaller than or equal to `assetToTransfer`,
                        // and their subtraction can't underflow
                        assetToTransfer -= missingValue - balanceVault;
                    }
                } else {
                    unchecked {
                        // as `missingValue` is smaller than or equal to `balanceVault`, this operation can't underflow
                        s._balanceVault = balanceVault - missingValue;
                    }
                }
            }

            if (assetToTransfer > 0) {
                address(s._asset).safeTransfer(long.to, assetToTransfer);
            }
        } else {
            // if the position value <= 0, including the fees and the Pyth confidence interval, no assets will be
            // transferred. However, the `closeBoundedPositionValue` must still be credited to the vault

            s._balanceVault += long.closeBoundedPositionValue;
        }

        isValidated_ = true;

        emit IUsdnProtocolEvents.ValidatedClosePosition(
            long.validator,
            long.to,
            Types.PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
            assetToTransfer,
            assetToTransfer.toInt256() - Utils._toInt256(long.closeAmount)
        );
    }
}
