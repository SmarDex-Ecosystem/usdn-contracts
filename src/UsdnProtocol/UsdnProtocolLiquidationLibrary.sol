// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdnProtocolActions } from "../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import {
    LongPendingAction,
    PendingAction,
    Position,
    PositionId,
    PreviousActionsData,
    ProtocolAction,
    TickData
} from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { Permit2TokenBitfield } from "../libraries/Permit2TokenBitfield.sol";
import { IOwnershipCallback } from "../interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { Storage } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from "./UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as longLib } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as actionsVaultLib } from "./UsdnProtocolActionsVaultLibrary.sol";
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

/**
 * @dev Structure to hold the transient data during `_initiateOpenPosition`
 * @param adjustedPrice The adjusted price with position fees applied
 * @param posId The new position id
 * @param liquidationPenalty The liquidation penalty
 * @param positionTotalExpo The total expo of the position
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct InitiateOpenPositionData {
    uint128 adjustedPrice;
    PositionId posId;
    uint8 liquidationPenalty;
    uint128 positionTotalExpo;
    bool isLiquidationPending;
}

/**
 * @dev Structure to hold the transient data during `_initiateClosePosition`
 * @param pos The position to close
 * @param liquidationPenalty The liquidation penalty
 * @param totalExpoToClose The total expo to close
 * @param lastPrice The price after the last balances update
 * @param tempPositionValue The bounded value of the position that was removed from the long balance
 * @param longTradingExpo The long trading expo
 * @param liqMulAcc The liquidation multiplier accumulator
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct ClosePositionData {
    Position pos;
    uint8 liquidationPenalty;
    uint128 totalExpoToClose;
    uint128 lastPrice;
    uint256 tempPositionValue;
    uint256 longTradingExpo;
    HugeUint.Uint512 liqMulAcc;
    bool isLiquidationPending;
}

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

/**
 * @dev Structure to hold the transient data during `_validateOpenPosition`
 * @param action The long pending action
 * @param startPrice The new entry price of the position
 * @param tickHash The tick hash
 * @param pos The position object
 * @param liqPriceWithoutPenalty The new liquidation price without penalty
 * @param leverage The new leverage
 * @param liquidationPenalty The liquidation penalty for the position's tick
 * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
 */
struct ValidateOpenPositionData {
    LongPendingAction action;
    uint128 startPrice;
    bytes32 tickHash;
    Position pos;
    uint128 liqPriceWithoutPenalty;
    uint128 leverage;
    uint8 liquidationPenalty;
    bool isLiquidationPending;
}

library UsdnProtocolLiquidationLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using Permit2TokenBitfield for Permit2TokenBitfield.Bitfield;

    // / @inheritdoc IUsdnProtocolActions
    function liquidate(Storage storage s, bytes calldata currentPriceData, uint16 iterations)
        public
        returns (uint256 liquidatedPositions_)
    {
        uint256 balanceBefore = address(this).balance;
        PriceInfo memory currentPrice =
            actionsVaultLib._getOraclePrice(s, ProtocolAction.Liquidation, 0, "", currentPriceData);

        (liquidatedPositions_,) = longLib._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            iterations,
            true,
            ProtocolAction.Liquidation,
            currentPriceData
        );

        actionsVaultLib._refundExcessEther(0, 0, balanceBefore);
        actionsVaultLib._checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function validateActionablePendingActions(
        Storage storage s,
        PreviousActionsData calldata previousActionsData,
        uint256 maxValidations
    ) public returns (uint256 validatedActions_) {
        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;

        if (maxValidations > previousActionsData.rawIndices.length) {
            maxValidations = previousActionsData.rawIndices.length;
        }
        do {
            (, bool executed, bool liq, uint256 securityDepositValue) =
                actionsVaultLib._executePendingAction(s, previousActionsData);
            if (!executed && !liq) {
                break;
            }
            unchecked {
                validatedActions_++;
                amountToRefund += securityDepositValue;
            }
        } while (validatedActions_ < maxValidations);
        actionsVaultLib._refundExcessEther(0, amountToRefund, balanceBefore);
        actionsVaultLib._checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function transferPositionOwnership(Storage storage s, PositionId calldata posId, address newOwner) public {
        (bytes32 tickHash, uint256 version) = vaultLib._tickHash(s, posId.tick);
        if (posId.tickVersion != version) {
            revert IUsdnProtocolErrors.UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        Position storage pos = s._longPositions[tickHash][posId.index];

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

        emit PositionOwnershipTransferred(posId, msg.sender, newOwner);
    }

    /**
     * @notice The close vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the close limit on the vault side, otherwise revert
     * @param posTotalExpoToClose The total expo to remove position
     * @param posValueToClose The value to remove from the position
     */
    function _checkImbalanceLimitClose(Storage storage s, uint256 posTotalExpoToClose, uint256 posValueToClose)
        public
        view
    {
        int256 closeExpoImbalanceLimitBps = s._closeExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (closeExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newLongBalance = s._balanceLong.toInt256().safeSub(posValueToClose.toInt256());
        uint256 newTotalExpo = s._totalExpo - posTotalExpoToClose;
        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault);

        int256 imbalanceBps = longLib._calcImbalanceCloseBps(s, currentVaultExpo, newLongBalance, newTotalExpo);

        if (imbalanceBps >= closeExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Send rewards to the liquidator
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain
     * @param liquidatedTicks The number of ticks that were liquidated
     * @param remainingCollateral The amount of collateral remaining after liquidations
     * @param rebased Whether a USDN rebase was performed
     * @param action The protocol action that triggered liquidations
     * @param rebaseCallbackResult The rebase callback result, if any
     * @param priceData The price oracle update data
     */
    function _sendRewardsToLiquidator(
        Storage storage s,
        uint16 liquidatedTicks,
        int256 remainingCollateral,
        bool rebased,
        ProtocolAction action,
        bytes memory rebaseCallbackResult,
        bytes memory priceData
    ) public {
        // get how much we should give to the liquidator as rewards
        uint256 liquidationRewards = s._liquidationRewardsManager.getLiquidationRewards(
            liquidatedTicks, remainingCollateral, rebased, action, rebaseCallbackResult, priceData
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

        emit LiquidatorRewarded(msg.sender, liquidationRewards);
    }

    /**
     * @notice Prepare the pending action struct for an open position and add it to the queue
     * @param to The address that will be the owner of the position
     * @param validator The address that will validate the open position
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The open position action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createOpenPendingAction(
        Storage storage s,
        address to,
        address validator,
        uint64 securityDepositValue,
        InitiateOpenPositionData memory data
    ) public returns (uint256 amountToRefund_) {
        LongPendingAction memory action = LongPendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            tick: data.posId.tick,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: data.posId.tickVersion,
            index: data.posId.index,
            closeLiqMultiplier: 0,
            closeBoundedPositionValue: 0
        });
        amountToRefund_ = coreLib._addPendingAction(s, validator, coreLib._convertLongPendingAction(action));
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the open position action
     * @param pending The pending action data
     * @param priceData The current price data
     * @return data_ The {ValidateOpenPosition} data struct
     * @return liquidated_ Whether the position was liquidated
     */
    function _prepareValidateOpenPositionData(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
        returns (ValidateOpenPositionData memory data_, bool liquidated_)
    {
        data_.action = coreLib._toLongPendingAction(pending);
        PriceInfo memory currentPrice = actionsVaultLib._getOraclePrice(
            s,
            ProtocolAction.ValidateOpenPosition,
            data_.action.timestamp,
            _calcActionId(data_.action.validator, data_.action.timestamp),
            priceData
        );
        // apply fees on price
        data_.startPrice = (currentPrice.price + currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        (, data_.isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.ValidateOpenPosition,
            priceData
        );

        uint256 version;
        (data_.tickHash, version) = vaultLib._tickHash(s, data_.action.tick);
        if (version != data_.action.tickVersion) {
            // the current tick version doesn't match the version from the pending action
            // this means the position has been liquidated in the meantime
            emit StalePendingActionRemoved(
                data_.action.validator,
                PositionId({ tick: data_.action.tick, tickVersion: data_.action.tickVersion, index: data_.action.index })
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
        data_.liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(
            s, longLib._calcTickWithoutPenalty(s, data_.action.tick, data_.liquidationPenalty)
        );
        // reverts if liqPriceWithoutPenalty >= startPrice
        data_.leverage = longLib._getLeverage(s, data_.startPrice, data_.liqPriceWithoutPenalty);
    }

    /**
     * @notice Perform checks for the initiate close position action
     * @dev Reverts if the to address is zero, the position was not validated yet, the position is not owned by the
     * user, the amount to close is higher than the position amount, or the amount to close is zero
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address of the validator
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param pos The position to close
     */
    function _checkInitiateClosePosition(
        Storage storage s,
        address owner,
        address to,
        address validator,
        uint128 amountToClose,
        Position memory pos
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
        if (amountToClose > pos.amount) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        // make sure the remaining position is higher than _minLongPosition
        // for the Rebalancer, we allow users to close their position fully in every case
        uint128 remainingAmount = pos.amount - amountToClose;
        if (remainingAmount > 0 && remainingAmount < s._minLongPosition) {
            IBaseRebalancer rebalancer = s._rebalancer;
            if (owner == address(rebalancer)) {
                uint128 userPosAmount = rebalancer.getUserDepositData(to).amount;
                if (amountToClose != userPosAmount) {
                    revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
                }
            } else {
                revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
            }
        }
        if (amountToClose == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountToCloseIsZero();
        }
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate close position action
     * @dev Reverts if the imbalance limit is reached, or if any of the checks in `_checkInitiateClosePosition` fail
     * Returns without creating a pending action if the position gets liquidated in this transaction
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address of the pending action validator
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     * @return data_ The close position data
     * @return liquidated_ Whether the position was liquidated and the caller should return early
     */
    function _prepareClosePositionData(
        Storage storage s,
        address owner,
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) public returns (ClosePositionData memory data_, bool liquidated_) {
        (data_.pos, data_.liquidationPenalty) = longLib.getLongPosition(s, posId);

        _checkInitiateClosePosition(s, owner, to, validator, amountToClose, data_.pos);

        PriceInfo memory currentPrice = actionsVaultLib._getOraclePrice(
            s,
            ProtocolAction.InitiateClosePosition,
            block.timestamp,
            _calcActionId(owner, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.InitiateClosePosition,
            currentPriceData
        );

        uint256 version = s._tickVersion[posId.tick];
        if (version != posId.tickVersion) {
            // the current tick version doesn't match the version from the position,
            // that means that the position has been liquidated in this transaction
            return (data_, true);
        }

        if (data_.isLiquidationPending) {
            return (data_, false);
        }

        data_.totalExpoToClose = (uint256(data_.pos.totalExpo) * amountToClose / data_.pos.amount).toUint128();

        data_.longTradingExpo = s._totalExpo - s._balanceLong;
        data_.liqMulAcc = s._liqMultiplierAccumulator;
        data_.lastPrice = s._lastPrice;

        // the approximate value position to remove is calculated with `_lastPrice`, so not taking into account
        // any fees. This way, the removal of the position doesn't affect the liquidation multiplier calculations

        // to have maximum precision, we do not pre-compute the liquidation multiplier with a fixed
        // precision just now, we will store it in the pending action later, to be used in the validate action
        int24 tick = longLib._calcTickWithoutPenalty(s, posId.tick, data_.liquidationPenalty);
        data_.tempPositionValue = _assetToRemove(
            s,
            data_.lastPrice,
            longLib.getEffectivePriceForTick(tick, data_.lastPrice, data_.longTradingExpo, data_.liqMulAcc),
            data_.totalExpoToClose
        );

        // we perform the imbalance check based on the estimated balance change since that's the best we have right now
        _checkImbalanceLimitClose(s, data_.totalExpoToClose, data_.tempPositionValue);
    }

    /**
     * @notice Prepare the pending action struct for the close position action and add it to the queue
     * @param validator The validator for the pending action
     * @param to The address that will receive the assets
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The close position data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createClosePendingAction(
        Storage storage s,
        address validator,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        ClosePositionData memory data
    ) public returns (uint256 amountToRefund_) {
        LongPendingAction memory action = LongPendingAction({
            action: ProtocolAction.ValidateClosePosition,
            timestamp: uint40(block.timestamp),
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            tick: posId.tick,
            closeAmount: amountToClose,
            closePosTotalExpo: data.totalExpoToClose,
            tickVersion: posId.tickVersion,
            index: posId.index,
            closeLiqMultiplier: longLib._calcFixedPrecisionMultiplier(
                s, data.lastPrice, data.longTradingExpo, data.liqMulAcc
            ),
            closeBoundedPositionValue: data.tempPositionValue
        });
        amountToRefund_ = coreLib._addPendingAction(s, validator, coreLib._convertLongPendingAction(action));
    }

    /**
     * @notice Calculate how much wstETH must be removed from the long balance due to a position closing
     * @dev The amount is bound by the amount of wstETH available on the long side
     * @param priceWithFees The current price of the asset, adjusted with fees
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @param posExpo The total expo of the position
     * @return boundedPosValue_ The amount of assets to remove from the long balance, bound by zero and the available
     * long balance
     */
    function _assetToRemove(Storage storage s, uint128 priceWithFees, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        public
        view
        returns (uint256 boundedPosValue_)
    {
        // the available amount of assets on the long side (with the current balance)
        uint256 available = s._balanceLong;

        // calculate position value
        int256 positionValue = longLib._positionValue(priceWithFees, liqPriceWithoutPenalty, posExpo);

        if (positionValue <= 0) {
            // should not happen, unless we did not manage to liquidate all ticks that needed to be liquidated during
            // the initiateClosePosition
            boundedPosValue_ = 0;
        } else if (uint256(positionValue) > available) {
            boundedPosValue_ = available;
        } else {
            boundedPosValue_ = uint256(positionValue);
        }
    }

    /**
     * @notice Remove the provided total amount from its position and update the tick data and position
     * @dev Note: this method does not update the long balance
     * If the amount to remove is greater than or equal to the position's total amount, the position is deleted instead
     * @param tick The tick to remove from
     * @param index Index of the position in the tick array
     * @param pos The position to remove the amount from
     * @param amountToRemove The amount to remove from the position
     * @param totalExpoToRemove The total expo to remove from the position
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _removeAmountFromPosition(
        Storage storage s,
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) public returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        (bytes32 tickHash,) = vaultLib._tickHash(s, tick);
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

            // remove from tick array (set to zero to avoid shifting indices)
            delete s._longPositions[tickHash][index];
            if (tickData.totalPos == 0) {
                // we removed the last position in the tick
                s._tickBitmap.unset(coreLib._calcBitmapIndexFromTick(s, tick));
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
     * @param tick The tick to hold the new position
     * @param long The position to save
     * @param liquidationPenalty The liquidation penalty for the tick
     * @return tickVersion_ The version of the tick
     * @return index_ The index of the position in the tick array
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _saveNewPosition(Storage storage s, int24 tick, Position memory long, uint8 liquidationPenalty)
        public
        returns (uint256 tickVersion_, uint256 index_, HugeUint.Uint512 memory liqMultiplierAccumulator_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = vaultLib._tickHash(s, tick);

        // add to tick array
        Position[] storage tickArray = s._longPositions[tickHash];
        index_ = tickArray.length;
        if (tick > s._highestPopulatedTick) {
            // keep track of the highest populated tick
            s._highestPopulatedTick = tick;
        }
        tickArray.push(long);

        // adjust state
        s._totalExpo += long.totalExpo;
        ++s._totalLongPositions;

        // update tick data
        TickData storage tickData = s._tickData[tickHash];
        // the unadjusted tick price for the accumulator might be different depending
        // if we already have positions in the tick or not
        uint256 unadjustedTickPrice;
        if (tickData.totalPos == 0) {
            // first position in this tick, we need to reflect that it is populated
            s._tickBitmap.set(coreLib._calcBitmapIndexFromTick(s, tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
            unadjustedTickPrice = TickMath.getPriceAtTick(tick - int24(uint24(liquidationPenalty)) * s._tickSpacing);
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's `liquidationPenalty` since it remains constant
            unadjustedTickPrice =
                TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
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
}
