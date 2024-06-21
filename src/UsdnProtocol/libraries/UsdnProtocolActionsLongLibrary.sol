// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolActions } from "../../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { Permit2TokenBitfield } from "../../libraries/Permit2TokenBitfield.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { Storage } from "../UsdnProtocolStorage.sol";
import { UsdnProtocolActionsUtilsLibrary as actionsUtilsLib } from "./UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as actionsVaultLib } from "./UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolConstantsLibrary as constantsLib } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as longLib } from "./UsdnProtocolLongLibrary.sol";

library UsdnProtocolActionsLongLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using HugeUint for HugeUint.Uint512;
    using Permit2TokenBitfield for Permit2TokenBitfield.Bitfield;

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions}
    function tickHash(int24 tick, uint256 version) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }

    /// @notice See {IUsdnProtocolActions}
    function initiateOpenPosition(
        Storage storage s,
        IUsdnProtocolTypes.InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData,
        IUsdnProtocolTypes.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_, IUsdnProtocolTypes.PositionId memory posId_) {
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
                amountToRefund += actionsVaultLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }
        actionsVaultLib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        actionsVaultLib._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function validateOpenPosition(
        Storage storage s,
        address payable validator,
        bytes calldata openPriceData,
        IUsdnProtocolTypes.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liquidated;
        (amountToRefund, success_, liquidated) = _validateOpenPosition(s, validator, openPriceData);
        if (msg.sender != validator) {
            actionsVaultLib._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_ || liquidated) {
            unchecked {
                amountToRefund += actionsVaultLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        actionsVaultLib._refundExcessEther(0, amountToRefund, balanceBefore);
        actionsVaultLib._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function initiateClosePosition(
        Storage storage s,
        IUsdnProtocolTypes.InitiateClosePositionParams memory params,
        bytes calldata currentPriceData,
        IUsdnProtocolTypes.PreviousActionsData calldata previousActionsData
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
                amountToRefund += actionsVaultLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        actionsVaultLib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        actionsVaultLib._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function validateClosePosition(
        Storage storage s,
        address payable validator,
        bytes calldata closePriceData,
        IUsdnProtocolTypes.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liq;
        (amountToRefund, success_, liq) = _validateClosePosition(s, validator, closePriceData);
        if (msg.sender != validator) {
            actionsVaultLib._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_ || liq) {
            unchecked {
                amountToRefund += actionsVaultLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        actionsVaultLib._refundExcessEther(0, amountToRefund, balanceBefore);
        actionsVaultLib._checkPendingFee(s);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initiate an open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateOpenPosition` action
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
        Storage storage s,
        IUsdnProtocolTypes.InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData
    ) public returns (IUsdnProtocolTypes.PositionId memory posId_, uint256 amountToRefund_, bool isInitiated_) {
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

        IUsdnProtocolTypes.InitiateOpenPositionData memory data = longLib._prepareInitiateOpenPositionData(
            s, params.validator, params.amount, params.desiredLiqPrice, currentPriceData
        );

        if (data.isLiquidationPending) {
            // value to indicate the position was not created
            posId_.tick = constantsLib.NO_POSITION_TICK;
            return (posId_, params.securityDepositValue, false);
        }

        // register position and adjust contract state
        IUsdnProtocolTypes.Position memory long = IUsdnProtocolTypes.Position({
            validated: false,
            user: params.to,
            amount: params.amount,
            totalExpo: data.positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });
        (data.posId.tickVersion, data.posId.index,) =
            actionsUtilsLib._saveNewPosition(s, data.posId.tick, long, data.liquidationPenalty);
        s._balanceLong += long.amount;
        posId_ = data.posId;

        amountToRefund_ =
            actionsUtilsLib._createOpenPendingAction(s, params.to, params.validator, params.securityDepositValue, data);

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
     * @notice Get the pending action data of the owner, try to validate it and clear it if successful
     * @param s The storage of the protocol
     * @param validator The address of the validator
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateOpenPosition(Storage storage s, address validator, bytes calldata priceData)
        public
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        (IUsdnProtocolTypes.PendingAction memory pending, uint128 rawIndex) =
            coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != IUsdnProtocolTypes.ProtocolAction.ValidateOpenPosition) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        (isValidated_, liquidated_) = _validateOpenPositionWithAction(s, pending, priceData);

        if (isValidated_ || liquidated_) {
            coreLib._clearPendingAction(s, validator, rawIndex);
            return (pending.securityDepositValue, isValidated_, liquidated_);
        }
    }

    struct MaxLeverageData {
        int24 tickWithoutPenalty;
        uint8 currentLiqPenalty;
        IUsdnProtocolTypes.PositionId newPosId;
        uint8 liquidationPenalty;
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
        Storage storage s,
        IUsdnProtocolTypes.PendingAction memory pending,
        bytes calldata priceData
    ) public returns (bool isValidated_, bool liquidated_) {
        (IUsdnProtocolTypes.ValidateOpenPositionData memory data, bool liquidated) =
            actionsUtilsLib._prepareValidateOpenPositionData(s, pending, priceData);

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
            data.liqPriceWithoutPenalty = longLib._getLiquidationPrice(data.startPrice, maxLeverage);
            // adjust to the closest valid tick down
            maxLeverageData.tickWithoutPenalty = longLib.getEffectiveTickForPrice(s, data.liqPriceWithoutPenalty);

            // apply liquidation penalty with the current penalty setting
            maxLeverageData.currentLiqPenalty = s._liquidationPenalty;
            maxLeverageData.newPosId;
            maxLeverageData.newPosId.tick =
                maxLeverageData.tickWithoutPenalty + int24(uint24(maxLeverageData.currentLiqPenalty)) * s._tickSpacing;
            // retrieve the actual penalty for this tick we want to use
            maxLeverageData.liquidationPenalty = longLib.getTickLiquidationPenalty(s, maxLeverageData.newPosId.tick);
            // check if the penalty for that tick is different from the current setting
            if (maxLeverageData.liquidationPenalty == maxLeverageData.currentLiqPenalty) {
                // since the tick's penalty is the same as what we assumed, we can use the `tickWithoutPenalty` from
                // above
                // retrieve the exact liquidation price without penalty
                data.liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(s, maxLeverageData.tickWithoutPenalty);
            } else {
                // the tick's imposed penalty is different from the current setting, so the `tickWithoutPenalty` we
                // calculated above can't be used to calculate the leverage
                // we must instead use the tick's penalty to find the new `liqPriceWithoutPenalty` and calculate the
                // leverage

                // note: In case the tick liquidation penalty is lower than the current setting, it might lead to a
                // leverage that exceeds the max leverage slightly. We allow this behavior in this rare occurrence

                // retrieve exact liquidation price without penalty
                data.liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(
                    s,
                    longLib._calcTickWithoutPenalty(
                        s, maxLeverageData.newPosId.tick, maxLeverageData.liquidationPenalty
                    )
                );
            }

            // move the position to its new tick, update its total expo, and return the new tickVersion and index
            // remove position from old tick completely
            actionsUtilsLib._removeAmountFromPosition(
                s, data.action.tick, data.action.index, data.pos, data.pos.amount, data.pos.totalExpo
            );
            // update position total expo (because of new leverage / liq price)
            data.pos.totalExpo =
                longLib._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);
            // mark the position as validated
            data.pos.validated = true;
            // insert position into new tick
            (maxLeverageData.newPosId.tickVersion, maxLeverageData.newPosId.index,) = actionsUtilsLib._saveNewPosition(
                s, maxLeverageData.newPosId.tick, data.pos, maxLeverageData.liquidationPenalty
            );
            // no long balance update is necessary (collateral didn't change)

            emit IUsdnProtocolEvents.LiquidationPriceUpdated(
                IUsdnProtocolTypes.PositionId({
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
        uint128 expoAfter =
            longLib._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);

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
            IUsdnProtocolTypes.TickData storage tickData = s._tickData[data.tickHash];
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.action.tick - int24(uint24(data.liquidationPenalty)) * s._tickSpacing);
            tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
            s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.add(
                HugeUint.wrap(expoAfter * unadjustedTickPrice)
            ).sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
        }

        isValidated_ = true;
        emit IUsdnProtocolEvents.ValidatedOpenPosition(
            data.action.to,
            data.action.validator,
            expoAfter,
            data.startPrice,
            IUsdnProtocolTypes.PositionId({
                tick: data.action.tick,
                tickVersion: data.action.tickVersion,
                index: data.action.index
            })
        );
    }

    /**
     * @notice Initiate a close position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action
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
        Storage storage s,
        address owner,
        address to,
        address validator,
        IUsdnProtocolTypes.PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) public returns (uint256 amountToRefund_, bool isInitiated_, bool liquidated_) {
        IUsdnProtocolTypes.ClosePositionData memory data;
        (data, liquidated_) =
            actionsUtilsLib._prepareClosePositionData(s, owner, to, validator, posId, amountToClose, currentPriceData);

        if (liquidated_ || data.isLiquidationPending) {
            // position was liquidated in this transaction or liquidations are pending
            return (securityDepositValue, !data.isLiquidationPending, liquidated_);
        }

        amountToRefund_ = actionsUtilsLib._createClosePendingAction(
            s, validator, to, posId, amountToClose, securityDepositValue, data
        );

        s._balanceLong -= data.tempPositionValue;

        actionsUtilsLib._removeAmountFromPosition(
            s, posId.tick, posId.index, data.pos, amountToClose, data.totalExpoToClose
        );

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
     * @notice Get the pending action data of the validator, try to validate it and clear it if successful
     * @param s The storage of the protocol
     * @param validator The validator of the pending action
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit of the pending action
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateClosePosition(Storage storage s, address validator, bytes calldata priceData)
        public
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        (IUsdnProtocolTypes.PendingAction memory pending, uint128 rawIndex) =
            coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        (isValidated_, liquidated_) = _validateClosePositionWithAction(s, pending, priceData);

        if (isValidated_ || liquidated_) {
            coreLib._clearPendingAction(s, validator, rawIndex);
            return (pending.securityDepositValue, isValidated_, liquidated_);
        }
    }

    struct ValidateClosePositionWithActionData {
        bool isLiquidationPending;
        uint128 priceWithFees;
        uint128 liquidationPrice;
        int256 positionValue;
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
        Storage storage s,
        IUsdnProtocolTypes.PendingAction memory pending,
        bytes calldata priceData
    ) public returns (bool isValidated_, bool liquidated_) {
        ValidateClosePositionWithActionData memory data;
        IUsdnProtocolTypes.LongPendingAction memory long = coreLib._toLongPendingAction(pending);

        PriceInfo memory currentPrice = actionsVaultLib._getOraclePrice(
            s,
            IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition,
            long.timestamp,
            actionsUtilsLib._calcActionId(long.validator, long.timestamp),
            priceData
        );

        (, data.isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition,
            priceData
        );

        // apply fees on price
        data.priceWithFees =
            (currentPrice.price - currentPrice.price * s._positionFeeBps / constantsLib.BPS_DIVISOR).toUint128();

        // get liquidation price (with liq penalty) to check if the position was valid at `timestamp + validationDelay`
        data.liquidationPrice = longLib._getEffectivePriceForTick(long.tick, long.closeLiqMultiplier);

        if (currentPrice.neutralPrice <= data.liquidationPrice) {
            // position should be liquidated, we don't transfer assets to the user
            // position was already removed from tick so no additional bookkeeping is necessary
            // credit the full amount to the vault to preserve the total balance invariant
            s._balanceVault += long.closeBoundedPositionValue;
            emit IUsdnProtocolEvents.LiquidatedPosition(
                long.validator, // not necessarily the position owner
                IUsdnProtocolTypes.PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
                currentPrice.neutralPrice,
                data.liquidationPrice
            );
            return (!data.isLiquidationPending, true);
        }

        if (data.isLiquidationPending) {
            return (false, false);
        }

        int24 tick = longLib._calcTickWithoutPenalty(s, long.tick, longLib.getTickLiquidationPenalty(s, long.tick));
        data.positionValue = longLib._positionValue(
            data.priceWithFees, longLib._getEffectivePriceForTick(tick, long.closeLiqMultiplier), long.closePosTotalExpo
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
            IUsdnProtocolTypes.PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
            assetToTransfer,
            assetToTransfer.toInt256() - coreLib._toInt256(long.closeAmount)
        );
    }
}
