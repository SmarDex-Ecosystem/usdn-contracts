// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolActions } from "../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import {
    DepositPendingAction,
    LiquidationsEffects,
    LongPendingAction,
    PendingAction,
    Position,
    PositionId,
    PreviousActionsData,
    ProtocolAction,
    TickData,
    WithdrawalPendingAction
} from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { Permit2TokenBitfield } from "../libraries/Permit2TokenBitfield.sol";
import { Storage } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as longLib } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as actionsVaultLib } from "./UsdnProtocolActionsVaultLibrary.sol";
import {
    UsdnProtocolLiquidationLibrary as actionsLiquidationLib,
    ClosePositionData,
    ValidateOpenPositionData,
    InitiateOpenPositionData
} from "./UsdnProtocolLiquidationLibrary.sol";
import { IUsdnProtocolErrors } from "./../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

struct InitiateClosePositionParams {
    PositionId posId;
    uint128 amountToClose;
    address to;
    address payable validator;
}

/**
 * @notice Emitted when a position changes ownership
 * @param posId The unique position ID
 * @param oldOwner The old owner
 * @param newOwner The new owner
 */
event PositionOwnershipTransferred(PositionId indexed posId, address indexed oldOwner, address indexed newOwner);

/**
 * @notice Emitted when a position is individually liquidated
 * @param user The validator of the close action, not necessarily the owner of the position
 * @param posId The unique identifier for the position that was liquidated
 * @param liquidationPrice The asset price at the moment of liquidation
 * @param effectiveTickPrice The effective liquidated tick price
 */
event LiquidatedPosition(address indexed user, PositionId posId, uint256 liquidationPrice, uint256 effectiveTickPrice);

/**
 * @notice Emitted when a user (liquidator) successfully liquidated positions
 * @param liquidator The address that initiated the liquidation
 * @param rewards The amount of tokens the liquidator received in rewards
 */
event LiquidatorRewarded(address indexed liquidator, uint256 rewards);

/**
 * @notice Emitted when a user initiates a deposit
 * @param to The address that will receive the USDN tokens
 * @param validator The address of the validator that will validate the deposit
 * @param amount The amount of assets that were deposited
 * @param timestamp The timestamp of the action
 */
event InitiatedDeposit(address indexed to, address indexed validator, uint256 amount, uint256 timestamp);

/**
 * @notice Emitted when a user validates a deposit
 * @param to The address that received the USDN tokens
 * @param validator The address of the validator that validated the deposit
 * @param amountDeposited The amount of assets that were deposited
 * @param usdnMinted The amount of USDN that was minted
 * @param timestamp The timestamp of the InitiatedDeposit action
 */
event ValidatedDeposit(
    address indexed to, address indexed validator, uint256 amountDeposited, uint256 usdnMinted, uint256 timestamp
);

/**
 * @notice Emitted when a user initiates a withdrawal
 * @param to The address that will receive the assets
 * @param validator The address of the validator that will validate the withdrawal
 * @param usdnAmount The amount of USDN that will be burned
 * @param timestamp The timestamp of the action
 */
event InitiatedWithdrawal(address indexed to, address indexed validator, uint256 usdnAmount, uint256 timestamp);

/**
 * @notice Emitted when a user validates a withdrawal
 * @param to The address that received the assets
 * @param validator The address of the validator that validated the withdrawal
 * @param amountWithdrawn The amount of assets that were withdrawn
 * @param usdnBurned The amount of USDN that was burned
 * @param timestamp The timestamp of the InitiatedWithdrawal action
 */
event ValidatedWithdrawal(
    address indexed to, address indexed validator, uint256 amountWithdrawn, uint256 usdnBurned, uint256 timestamp
);

/**
 * @notice Emitted when a user initiates the opening of a long position
 * @param owner The address that owns the position
 * @param validator The address of the validator that will validate the position
 * @param timestamp The timestamp of the action
 * @param totalExpo The initial total expo of the position (pending validation)
 * @param amount The amount of assets that were deposited as collateral
 * @param startPrice The asset price at the moment of the position creation (pending validation)
 * @param posId The unique position identifier
 */
event InitiatedOpenPosition(
    address indexed owner,
    address indexed validator,
    uint40 timestamp,
    uint128 totalExpo,
    uint128 amount,
    uint128 startPrice,
    PositionId posId
);

/**
 * @notice Emitted when a user validates the opening of a long position
 * @param owner The address that owns the position
 * @param validator The address of the validator that validated the position
 * @param totalExpo The total expo of the position
 * @param newStartPrice The asset price at the moment of the position creation (final)
 * @param posId The unique position identifier
 * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceUpdated` will be emitted too
 */
event ValidatedOpenPosition(
    address indexed owner, address indexed validator, uint128 totalExpo, uint128 newStartPrice, PositionId posId
);

/**
 * @notice Emitted when a user's position was liquidated while pending validation and we removed the pending action
 * @param validator The validator address
 * @param posId The unique position identifier
 */
event StalePendingActionRemoved(address indexed validator, PositionId posId);

/**
 * @notice Emitted when a position was moved from one tick to another
 * @param oldPosId The old position identifier
 * @param newPosId The new position identifier
 */
event LiquidationPriceUpdated(PositionId indexed oldPosId, PositionId newPosId);

/**
 * @notice Emitted when a user initiates the closing of all or part of a long position
 * @param owner The owner of this position
 * @param validator The validator for the pending action
 * @param to The address that will receive the assets
 * @param posId The unique position identifier
 * @param originalAmount The amount of collateral originally on the position
 * @param amountToClose The amount of collateral to close from the position
 * If the entirety of the position is being closed, this value equals `originalAmount`
 * @param totalExpoRemaining The total expo remaining in the position
 * If the entirety of the position is being closed, this value is zero
 */
event InitiatedClosePosition(
    address indexed owner,
    address indexed validator,
    address indexed to,
    PositionId posId,
    uint128 originalAmount,
    uint128 amountToClose,
    uint128 totalExpoRemaining
);

/**
 * @notice Emitted when a user validates the closing of a long position
 * @param validator The validator of the close action, not necessarily the position owner
 * @param to The address that received the assets
 * @param posId The unique position identifier
 * @param amountReceived The amount of assets that were sent to the user
 * @param profit The profit that the user made
 */
event ValidatedClosePosition(
    address indexed validator, address indexed to, PositionId posId, uint256 amountReceived, int256 profit
);

/**
 * @notice Emitted when a security deposit is refunded
 * @param pendingActionValidator Address of the validator
 * @param receivedBy Address of the user who received the security deposit
 * @param amount Amount of security deposit refunded
 */
event SecurityDepositRefunded(address indexed pendingActionValidator, address indexed receivedBy, uint256 amount);

/**
 * @notice Emitted when the pending protocol fee is distributed
 * @param feeCollector The collector's address
 * @param amount The amount of fee transferred
 */
event ProtocolFeeDistributed(address feeCollector, uint256 amount);

/**
 * @notice Emitted when a tick is liquidated
 * @param tick The liquidated tick
 * @param oldTickVersion The liquidated tick version
 * @param liquidationPrice The asset price at the moment of liquidation
 * @param effectiveTickPrice The effective liquidated tick price
 * @param remainingCollateral The amount of asset that was left in the tick, which was transferred to the vault if
 * positive, or was taken from the vault if negative
 */
event LiquidatedTick(
    int24 indexed tick,
    uint256 indexed oldTickVersion,
    uint256 liquidationPrice,
    uint256 effectiveTickPrice,
    int256 remainingCollateral
);

/**
 * @notice Parameters for the internal `_initiateOpenPosition` function
 * @param user The address of the user initiating the open position
 * @param to The address that will be the owner of the position
 * @param validator The address that will validate the open position
 * @param amount The amount of wstETH to deposit
 * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty
 * @param securityDepositValue The value of the security deposit for the newly created pending action
 * @param permit2TokenBitfield The permit2 bitfield
 * @param currentPriceData The current price data (used to calculate the temporary leverage and entry price,
 * pending validation)
 */
struct InitiateOpenPositionParams {
    address user;
    address to;
    address validator;
    uint128 amount;
    uint128 desiredLiqPrice;
    uint64 securityDepositValue;
    Permit2TokenBitfield.Bitfield permit2TokenBitfield;
}

library UsdnProtocolActionsLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using Permit2TokenBitfield for Permit2TokenBitfield.Bitfield;

    /**
     * @dev Structure to hold the transient data during `_initiateDeposit`
     * @param pendingActionPrice The adjusted price with position fees applied
     * @param isLiquidationPending Whether some liquidations still need to be performed
     * @param totalExpo The total expo of the long side
     * @param balanceLong The long side balance
     * @param balanceVault The vault side balance, calculated according to the pendingActionPrice
     * @param usdnTotalShares Total minted shares of USDN
     * @param sdexToBurn The amount of SDEX to burn for the deposit
     */
    struct InitiateDepositData {
        uint128 pendingActionPrice;
        bool isLiquidationPending;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint256 usdnTotalShares;
        uint256 sdexToBurn;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateWithdrawal`
     * @param pendingActionPrice The adjusted price with position fees applied
     * @param usdnTotalShares The total shares supply of USDN
     * @param totalExpo The current total expo
     * @param balanceLong The current long balance
     * @param balanceVault The vault balance, adjusted according to the pendingActionPrice
     * @param withdrawalAmount The predicted amount of assets that will be withdrawn
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct WithdrawalData {
        uint128 pendingActionPrice;
        uint256 usdnTotalShares;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint256 withdrawalAmount;
        bool isLiquidationPending;
    }

    // / @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        Storage storage s,
        InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) public returns (bool success_, PositionId memory posId_) {
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

    // / @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(
        Storage storage s,
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
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

    // / @inheritdoc IUsdnProtocolActions
    function initiateClosePosition(
        Storage storage s,
        InitiateClosePositionParams memory params,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
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

    // / @inheritdoc IUsdnProtocolActions
    function validateClosePosition(
        Storage storage s,
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
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

    /**
     * @notice Initiate an open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateOpenPosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data
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
        InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData
    ) public returns (PositionId memory posId_, uint256 amountToRefund_, bool isInitiated_) {
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

        InitiateOpenPositionData memory data = longLib._prepareInitiateOpenPositionData(
            s, params.validator, params.amount, params.desiredLiqPrice, currentPriceData
        );

        if (data.isLiquidationPending) {
            // value to indicate the position was not created
            posId_.tick = s.NO_POSITION_TICK;
            return (posId_, params.securityDepositValue, false);
        }

        // register position and adjust contract state
        Position memory long = Position({
            validated: false,
            user: params.to,
            amount: params.amount,
            totalExpo: data.positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });
        (data.posId.tickVersion, data.posId.index,) =
            actionsLiquidationLib._saveNewPosition(s, data.posId.tick, long, data.liquidationPenalty);
        s._balanceLong += long.amount;
        posId_ = data.posId;

        amountToRefund_ = actionsLiquidationLib._createOpenPendingAction(
            s, params.to, params.validator, params.securityDepositValue, data
        );

        if (params.permit2TokenBitfield.useForAsset()) {
            address(s._asset).permit2TransferFrom(params.user, address(this), params.amount);
        } else {
            address(s._asset).safeTransferFrom(params.user, address(this), params.amount);
        }

        isInitiated_ = true;
        emit InitiatedOpenPosition(
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
        (PendingAction memory pending, uint128 rawIndex) = coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != ProtocolAction.ValidateOpenPosition) {
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
        PositionId newPosId;
        uint8 liquidationPenalty;
    }

    /**
     * @notice Validate an open position action
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateOpenPositionWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
        returns (bool isValidated_, bool liquidated_)
    {
        (ValidateOpenPositionData memory data, bool liquidated) =
            actionsLiquidationLib._prepareValidateOpenPositionData(s, pending, priceData);

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
            data.liqPriceWithoutPenalty = longLib._getLiquidationPrice(s, data.startPrice, maxLeverage);
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
            actionsLiquidationLib._removeAmountFromPosition(
                s, data.action.tick, data.action.index, data.pos, data.pos.amount, data.pos.totalExpo
            );
            // update position total expo (because of new leverage / liq price)
            data.pos.totalExpo =
                longLib._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);
            // mark the position as validated
            data.pos.validated = true;
            // insert position into new tick
            (maxLeverageData.newPosId.tickVersion, maxLeverageData.newPosId.index,) = actionsLiquidationLib
                ._saveNewPosition(s, maxLeverageData.newPosId.tick, data.pos, maxLeverageData.liquidationPenalty);
            // no long balance update is necessary (collateral didn't change)

            emit LiquidationPriceUpdated(
                PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index }),
                maxLeverageData.newPosId
            );
            emit ValidatedOpenPosition(
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
            TickData storage tickData = s._tickData[data.tickHash];
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.action.tick - int24(uint24(data.liquidationPenalty)) * s._tickSpacing);
            tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
            s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.add(
                HugeUint.wrap(expoAfter * unadjustedTickPrice)
            ).sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
        }

        isValidated_ = true;
        emit ValidatedOpenPosition(
            data.action.to,
            data.action.validator,
            expoAfter,
            data.startPrice,
            PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index })
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
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) public returns (uint256 amountToRefund_, bool isInitiated_, bool liquidated_) {
        ClosePositionData memory data;
        (data, liquidated_) = actionsLiquidationLib._prepareClosePositionData(
            s, owner, to, validator, posId, amountToClose, currentPriceData
        );

        if (liquidated_ || data.isLiquidationPending) {
            // position was liquidated in this transaction or liquidations are pending
            return (securityDepositValue, !data.isLiquidationPending, liquidated_);
        }

        amountToRefund_ = actionsLiquidationLib._createClosePendingAction(
            s, validator, to, posId, amountToClose, securityDepositValue, data
        );

        s._balanceLong -= data.tempPositionValue;

        actionsLiquidationLib._removeAmountFromPosition(
            s, posId.tick, posId.index, data.pos, amountToClose, data.totalExpoToClose
        );

        isInitiated_ = true;
        emit InitiatedClosePosition(
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
        (PendingAction memory pending, uint128 rawIndex) = coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != ProtocolAction.ValidateClosePosition) {
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
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateClosePositionWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
        returns (bool isValidated_, bool liquidated_)
    {
        ValidateClosePositionWithActionData memory data;
        LongPendingAction memory long = coreLib._toLongPendingAction(pending);

        PriceInfo memory currentPrice = actionsVaultLib._getOraclePrice(
            s,
            ProtocolAction.ValidateClosePosition,
            long.timestamp,
            actionsLiquidationLib._calcActionId(long.validator, long.timestamp),
            priceData
        );

        (, data.isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.ValidateClosePosition,
            priceData
        );

        // apply fees on price
        data.priceWithFees = (currentPrice.price - currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        // get liquidation price (with liq penalty) to check if the position was valid at `timestamp + validationDelay`
        data.liquidationPrice = longLib._getEffectivePriceForTick(s, long.tick, long.closeLiqMultiplier);

        if (currentPrice.neutralPrice <= data.liquidationPrice) {
            // position should be liquidated, we don't transfer assets to the user
            // position was already removed from tick so no additional bookkeeping is necessary
            // credit the full amount to the vault to preserve the total balance invariant
            s._balanceVault += long.closeBoundedPositionValue;
            emit LiquidatedPosition(
                long.validator, // not necessarily the position owner
                PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
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
            data.priceWithFees,
            longLib._getEffectivePriceForTick(s, tick, long.closeLiqMultiplier),
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

        emit ValidatedClosePosition(
            long.validator, // not necessarily the position owner
            long.to,
            PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
            assetToTransfer,
            assetToTransfer.toInt256() - coreLib._toInt256(long.closeAmount)
        );
    }
}
