// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolActions } from "../../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { Permit2TokenBitfield } from "../../libraries/Permit2TokenBitfield.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as ActionsVault } from "./UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";

library UsdnProtocolActionsLongLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using HugeUint for HugeUint.Uint512;
    using Permit2TokenBitfield for Permit2TokenBitfield.Bitfield;
    using LibBitmap for LibBitmap.Bitmap;

    /**
     * @notice Data structure for the `_validateClosePositionWithAction` function
     * @param isLiquidationPending Whether a liquidation is pending
     * @param priceWithFees The price of the position with fees
     * @param liquidationPrice The liquidation price of the position
     * @param positionValue The value of the position. The amount the user will receive when closing the position
     */
    struct ValidateClosePositionWithActionData {
        bool isLiquidationPending;
        uint128 priceWithFees;
        uint128 liquidationPrice;
        int256 positionValue;
    }

    /**
     * @notice Data structure for the `_validateOpenPositionWithAction` function
     * @param currentLiqPenalty The current liquidation penalty parameter value
     * @param newPosId The new position id
     * @param liquidationPenalty The liquidation penalty of the tick we are considering
     */
    struct MaxLeverageData {
        uint24 currentLiqPenalty;
        Types.PositionId newPosId;
        uint24 liquidationPenalty;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions}
    function initiateOpenPosition(
        Types.Storage storage s,
        Types.InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_, Types.PositionId memory posId_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        params.securityDepositValue = securityDepositValue;
        uint256 amountToRefund;
        (posId_, amountToRefund, success_) = _initiateOpenPosition(s, params, currentPriceData);

        if (success_) {
            unchecked {
                amountToRefund += ActionsVault._executePendingActionOrRevert(s, previousActionsData);
            }
        }
        ActionsVault._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        ActionsVault._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function validateOpenPosition(
        Types.Storage storage s,
        address payable validator,
        bytes calldata openPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liquidated;
        (amountToRefund, success_, liquidated) = _validateOpenPosition(s, validator, openPriceData);
        if (msg.sender != validator) {
            ActionsVault._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_ || liquidated) {
            unchecked {
                amountToRefund += ActionsVault._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        ActionsVault._refundExcessEther(0, amountToRefund, balanceBefore);
        ActionsVault._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function initiateClosePosition(
        Types.Storage storage s,
        Types.InitiateClosePositionParams memory params,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liq;
        (amountToRefund, success_, liq) = _initiateClosePosition(
            s,
            msg.sender,
            params.to,
            params.validator,
            params.posId,
            params.amountToClose,
            securityDepositValue,
            currentPriceData
        );

        if (success_ || liq) {
            unchecked {
                amountToRefund += ActionsVault._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        ActionsVault._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        ActionsVault._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function validateClosePosition(
        Types.Storage storage s,
        address payable validator,
        bytes calldata closePriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liq;
        (amountToRefund, success_, liq) = _validateClosePosition(s, validator, closePriceData);
        if (msg.sender != validator) {
            ActionsVault._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_ || liq) {
            unchecked {
                amountToRefund += ActionsVault._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        ActionsVault._refundExcessEther(0, amountToRefund, balanceBefore);
        ActionsVault._checkPendingFee(s);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initiate an open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `Types.ProtocolAction.InitiateOpenPosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data
     * @param s The storage of the protocol
     * @param params The parameters for the open position initiation
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @return posId_ The unique index of the opened position
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     */
    function _initiateOpenPosition(
        Types.Storage storage s,
        Types.InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData
    ) public returns (Types.PositionId memory posId_, uint256 amountToRefund_, bool isInitiated_) {
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
            s, params.validator, params.amount, params.desiredLiqPrice, currentPriceData
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
            _saveNewPosition(s, data.posId.tick, long, data.liquidationPenalty);
        // because of the position fee, the position value is smaller than the amount
        s._balanceLong += data.positionValue;
        // positionValue must be smaller than or equal to amount, because the adjustedPrice (with fee) is larger than
        // or equal to the current price
        s._balanceVault += long.amount - data.positionValue;
        posId_ = data.posId;

        amountToRefund_ = _createOpenPendingAction(s, params.to, params.validator, params.securityDepositValue, data);

        if (params.permit2TokenBitfield.useForAsset()) {
            address(s._asset).permit2TransferFrom(params.user, address(this), params.amount);
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
    ) internal returns (uint256 amountToRefund_) {
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
        amountToRefund_ = Core._addPendingAction(s, validator, Utils._convertLongPendingAction(action));
    }

    /**
     * @notice Get the pending action data of the owner, try to validate it and clear it if successful
     * @param s The storage of the protocol
     * @param validator The address of the validator
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateOpenPosition(Types.Storage storage s, address validator, bytes calldata priceData)
        public
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateOpenPosition) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        (isValidated_, liquidated_) = _validateOpenPositionWithAction(s, pending, priceData);

        if (isValidated_ || liquidated_) {
            ActionsVault._clearPendingAction(s, validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
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
    ) internal returns (Types.ValidateOpenPositionData memory data_, bool liquidated_) {
        data_.action = Utils._toLongPendingAction(pending);
        PriceInfo memory currentPrice = ActionsVault._getOraclePrice(
            s,
            Types.ProtocolAction.ValidateOpenPosition,
            data_.action.timestamp,
            Utils._calcActionId(data_.action.validator, data_.action.timestamp),
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
        (data_.tickHash, version) = Utils._tickHash(s, data_.action.tick);
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
        data_.leverage = Utils._getLeverage(data_.startPrice, data_.liqPriceWithoutPenalty);
        // calculate how much the position that was opened in the initiate is now worth (it might be too large or too
        // small considering the new entry price). We will adjust the long and vault balances accordingly
        uint128 lastPrice = s._lastPrice;
        // multiplication cannot overflow because operands are uint128
        // lastPrice is larger than liqPriceWithoutPenalty because we performed liquidations above and would early
        // return in case of liquidation of this position
        data_.oldPosValue = Utils.positionValue(data_.pos.totalExpo, lastPrice, data_.liqPriceWithoutPenalty);
    }

    /**
     * @notice Validate an open position action
     * @param s The storage of the protocol
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateOpenPositionWithAction(
        Types.Storage storage s,
        Types.PendingAction memory pending,
        bytes calldata priceData
    ) public returns (bool isValidated_, bool liquidated_) {
        (Types.ValidateOpenPositionData memory data, bool liquidated) =
            _prepareValidateOpenPositionData(s, pending, priceData);

        if (liquidated) {
            return (!data.isLiquidationPending, true);
        }

        if (data.isLiquidationPending) {
            return (false, false);
        }

        // leverage is always greater than one (`liquidationPrice` is positive)
        // even if it drops below _minLeverage between the initiate and validate actions, we still allow it
        // however, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        uint128 maxLeverage = uint128(s._maxLeverage);
        if (data.leverage > maxLeverage) {
            MaxLeverageData memory maxLeverageData;
            // theoretical liquidation price for _maxLeverage
            data.liqPriceWithoutPenalty = Utils._getLiquidationPrice(data.startPrice, maxLeverage);
            // find corresponding tick and actual liq price with current penalty setting
            maxLeverageData.currentLiqPenalty = s._liquidationPenalty;
            (maxLeverageData.newPosId.tick, data.liqPriceWithoutPenalty) = Long._getTickFromDesiredLiqPrice(
                data.liqPriceWithoutPenalty,
                data.action.liqMultiplier,
                s._tickSpacing,
                maxLeverageData.currentLiqPenalty
            );

            // retrieve the actual penalty for this tick we want to use
            maxLeverageData.liquidationPenalty = Long.getTickLiquidationPenalty(s, maxLeverageData.newPosId.tick);
            // check if the penalty for that tick is different from the current setting
            // if the penalty is the same, then the `data.liqPriceWithoutPenalty` is the correct liquidation price
            // already
            if (maxLeverageData.liquidationPenalty != maxLeverageData.currentLiqPenalty) {
                // the tick's imposed penalty is different from the current setting, so the `liqPriceWithoutPenalty` we
                // got above can't be used to calculate the leverage
                // we must instead use the tick's penalty to find the new `liqPriceWithoutPenalty` and calculate the
                // total expo

                // note: In case the tick liquidation penalty is lower than the current setting, it might lead to a
                // leverage that exceeds the max leverage slightly. We allow this behavior in this rare occurrence

                // retrieve exact liquidation price without penalty
                // we consider the liquidation multiplier as it was during the initiation, to account for any funding
                // that was due between the initiation and the validation
                data.liqPriceWithoutPenalty = Utils._getEffectivePriceForTick(
                    Utils.calcTickWithoutPenalty(maxLeverageData.newPosId.tick, maxLeverageData.liquidationPenalty),
                    data.action.liqMultiplier
                );
            }

            // move the position to its new tick, update its total expo, and return the new tickVersion and index
            // remove position from old tick completely
            _removeAmountFromPosition(
                s, data.action.tick, data.action.index, data.pos, data.pos.amount, data.pos.totalExpo
            );
            // update position total expo (because of new leverage / liq price)
            data.pos.totalExpo =
                Utils._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);
            // mark the position as validated
            data.pos.validated = true;
            // insert position into new tick
            (maxLeverageData.newPosId.tickVersion, maxLeverageData.newPosId.index,) =
                _saveNewPosition(s, maxLeverageData.newPosId.tick, data.pos, maxLeverageData.liquidationPenalty);

            // adjust the balances to reflect the new value of the position
            uint256 updatedPosValue =
                Utils.positionValue(data.pos.totalExpo, data.currentPrice, data.liqPriceWithoutPenalty);
            _validateOpenPositionUpdateBalances(s, updatedPosValue, data.oldPosValue);

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

            return (true, false);
        }
        // calculate the new total expo
        uint128 expoBefore = data.pos.totalExpo;
        uint128 expoAfter = Utils._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);

        // update the total expo of the position
        data.pos.totalExpo = expoAfter;
        // mark the position as validated
        data.pos.validated = true;
        // SSTORE
        s._longPositions[data.tickHash][data.action.index] = data.pos;
        // update the total expo by adding the position's new expo and removing the old one
        // do not use += or it will underflow
        s._totalExpo = s._totalExpo + expoAfter - expoBefore;

        // update the tick data and the liqMultiplierAccumulator
        {
            Types.TickData storage tickData = s._tickData[data.tickHash];
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(Utils.calcTickWithoutPenalty(data.action.tick, data.liquidationPenalty));
            tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
            s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.add(
                HugeUint.wrap(expoAfter * unadjustedTickPrice)
            ).sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
        }

        // adjust the balances to reflect the new value of the position
        uint256 newPosValue = Utils.positionValue(expoAfter, data.currentPrice, data.liqPriceWithoutPenalty);
        _validateOpenPositionUpdateBalances(s, newPosValue, data.oldPosValue);

        isValidated_ = true;
        emit IUsdnProtocolEvents.ValidatedOpenPosition(
            data.action.to,
            data.action.validator,
            expoAfter,
            data.startPrice,
            Types.PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index })
        );
    }

    /**
     * @notice Initiate a close position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `Types.ProtocolAction.InitiateClosePosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and this function will return 0
     * The position is taken out of the tick and put in a pending state during this operation. Thus, calculations don't
     * consider this position anymore. The exit price (and thus profit) is not yet set definitively and will be done
     * during the `validate` action
     * @param s The storage of the protocol
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address that will validate the close action
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     * @return liquidated_ Whether the position was liquidated
     */
    function _initiateClosePosition(
        Types.Storage storage s,
        address owner,
        address to,
        address validator,
        Types.PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) public returns (uint256 amountToRefund_, bool isInitiated_, bool liquidated_) {
        Types.ClosePositionData memory data;
        (data, liquidated_) =
            ActionsUtils._prepareClosePositionData(s, owner, to, validator, posId, amountToClose, currentPriceData);

        if (liquidated_ || data.isLiquidationPending) {
            // position was liquidated in this transaction or liquidations are pending
            return (securityDepositValue, !data.isLiquidationPending, liquidated_);
        }

        amountToRefund_ = _createClosePendingAction(s, to, validator, posId, amountToClose, securityDepositValue, data);

        s._balanceLong -= data.tempPositionValue;

        _removeAmountFromPosition(s, posId.tick, posId.index, data.pos, amountToClose, data.totalExpoToClose);

        isInitiated_ = true;
        emit IUsdnProtocolEvents.InitiatedClosePosition(
            data.pos.user,
            validator,
            to,
            posId,
            data.pos.amount,
            amountToClose,
            data.pos.totalExpo - data.totalExpoToClose
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
        amountToRefund_ = Core._addPendingAction(s, validator, Utils._convertLongPendingAction(action));
    }

    /**
     * @notice Get the pending action data of the validator, try to validate it and clear it if successful
     * @param s The storage of the protocol
     * @param validator The validator of the pending action
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit of the pending action
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateClosePosition(Types.Storage storage s, address validator, bytes calldata priceData)
        public
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateClosePosition) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        (isValidated_, liquidated_) = _validateClosePositionWithAction(s, pending, priceData);

        if (isValidated_ || liquidated_) {
            ActionsVault._clearPendingAction(s, validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the close position action
     * @param s The storage of the protocol
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateClosePositionWithAction(
        Types.Storage storage s,
        Types.PendingAction memory pending,
        bytes calldata priceData
    ) public returns (bool isValidated_, bool liquidated_) {
        ValidateClosePositionWithActionData memory data;
        Types.LongPendingAction memory long = Utils._toLongPendingAction(pending);

        PriceInfo memory currentPrice = ActionsVault._getOraclePrice(
            s,
            Types.ProtocolAction.ValidateClosePosition,
            long.timestamp,
            Utils._calcActionId(long.validator, long.timestamp),
            priceData
        );

        (, data.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
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
            return (!data.isLiquidationPending, true);
        }

        if (data.isLiquidationPending) {
            return (false, false);
        }

        int24 tickWithoutPenalty = Utils.calcTickWithoutPenalty(long.tick, long.closeLiqPenalty);
        data.positionValue = Utils._positionValue(
            data.priceWithFees,
            Utils._getEffectivePriceForTick(tickWithoutPenalty, long.liqMultiplier),
            long.closePosTotalExpo
        );

        uint256 assetToTransfer;
        if (data.positionValue > 0) {
            assetToTransfer = uint256(data.positionValue);
            // normally, the position value should be smaller than `long.closeBoundedPositionValue` (due to the position
            // fee)
            // we can send the difference (any remaining collateral) to the vault
            // if the price increased since the initiation, it's possible that the position value is higher than the
            // `long.closeBoundedPositionValue`. In that case, we need to take the missing assets from the vault
            if (assetToTransfer < long.closeBoundedPositionValue) {
                uint256 remainingCollateral;
                unchecked {
                    // since assetToTransfer is strictly smaller than closeBoundedPositionValue, this operation can't
                    // underflow
                    remainingCollateral = long.closeBoundedPositionValue - assetToTransfer;
                }
                s._balanceVault += remainingCollateral;
            } else if (assetToTransfer > long.closeBoundedPositionValue) {
                uint256 missingValue;
                unchecked {
                    // since assetToTransfer is strictly larger than closeBoundedPositionValue, this operation can't
                    // underflow
                    missingValue = assetToTransfer - long.closeBoundedPositionValue;
                }
                uint256 balanceVault = s._balanceVault;
                // if the vault does not have enough balance left to pay out the missing value, we take what we can
                if (missingValue > balanceVault) {
                    s._balanceVault = 0;
                    unchecked {
                        // since `missingValue` is strictly larger than `balanceVault`, their subtraction can't
                        // underflow
                        // moreover, since (missingValue - balanceVault) is smaller than or equal to `missingValue`,
                        // and since `missingValue` is smaller than or equal to `assetToTransfer`,
                        // (missingValue - balanceVault) is smaller than or equal to `assetToTransfer`, and their
                        // subtraction can't underflow
                        assetToTransfer -= missingValue - balanceVault;
                    }
                } else {
                    unchecked {
                        // as `missingValue` is smaller than or equal to `balanceVault`, this operation can't underflow
                        s._balanceVault = balanceVault - missingValue;
                    }
                }
            }
        }
        // in case the position value is zero or negative, we don't transfer any asset to the user

        // send the asset to the user
        if (assetToTransfer > 0) {
            address(s._asset).safeTransfer(long.to, assetToTransfer);
        }

        isValidated_ = true;

        emit IUsdnProtocolEvents.ValidatedClosePosition(
            long.validator, // not necessarily the position owner
            long.to,
            Types.PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
            assetToTransfer,
            assetToTransfer.toInt256() - Utils.toInt256(long.closeAmount)
        );
    }

    /**
     * @notice Update the protocol balances during `validateOpenPosition` to reflect the new entry price of the
     * position
     * @dev We need to adjust the balances because the position that was created during the `initiateOpenPosition` might
     * have gained or lost some value, and we need to reflect that the position value is now `newPosValue`
     * Any potential PnL on that temporary position must be "cancelled" so that it doesn't affect the other positions
     * and the vault
     * @param s The storage of the protocol
     * @param newPosValue The new value of the position
     * @param oldPosValue The value of the position at the current price, using its old parameters
     */
    function _validateOpenPositionUpdateBalances(Types.Storage storage s, uint256 newPosValue, uint256 oldPosValue)
        private
    {
        if (newPosValue > oldPosValue) {
            // the long side is missing some value, we need to take it from the vault
            uint256 diff = newPosValue - oldPosValue;
            s._balanceVault -= diff;
            s._balanceLong += diff;
        } else if (newPosValue < oldPosValue) {
            // the long side has too much value, we need to give it to the vault side
            uint256 diff = oldPosValue - newPosValue;
            s._balanceVault += diff;
            s._balanceLong -= diff;
        }
        // if both are equal, no action is needed
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
        (tickHash, tickVersion_) = Utils._tickHash(s, tick);

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
            s._tickBitmap.set(Utils._calcBitmapIndexFromTick(s, tick));
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
        (bytes32 tickHash,) = Utils._tickHash(s, tick);
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
                s._tickBitmap.unset(Utils._calcBitmapIndexFromTick(s, tick));
            }
        }

        s._totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
        liqMultiplierAccumulator_ =
            s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * totalExpoToRemove));
        s._liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }
}
