// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

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
import { HugeUint } from "src/libraries/HugeUint.sol";
import { Storage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { UsdnProtocolCommonLibrary as commonLib } from "src/UsdnProtocol/UsdnProtocolCommonLibrary.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library UsdnProtocolActionsLibrary {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using HugeUint for HugeUint.Uint512;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SafeERC20 for IERC20Metadata;

    /**
     * @notice Emitted when a security deposit is refunded
     * @param paidBy Address of the user who paid the security deposit
     * @param receivedBy Address of the user who received the security deposit
     * @param amount Amount of security deposit refunded
     */
    event SecurityDepositRefunded(address indexed paidBy, address indexed receivedBy, uint256 amount);

    /**
     * @notice Emitted when a position was moved from one tick to another
     * @param oldPosId The old position identifier
     * @param newPosId The new position identifier
     */
    event LiquidationPriceUpdated(PositionId indexed oldPosId, PositionId newPosId);

    /**
     * @notice Emitted when a position is individually liquidated
     * @param user The user address
     * @param posId The unique identifier for the position that was liquidated
     * @param liquidationPrice The asset price at the moment of liquidation
     * @param effectiveTickPrice The effective liquidated tick price
     */
    event LiquidatedPosition(
        address indexed user, PositionId posId, uint256 liquidationPrice, uint256 effectiveTickPrice
    );

    /**
     * @notice Emitted when a user validates the closing of a long position
     * @param user The user address
     * @param to The address that received the assets
     * @param posId The unique position identifier
     * @param amountReceived The amount of asset that were sent to the user
     * @param profit The profit that the user made
     */
    event ValidatedClosePosition(
        address indexed user, address indexed to, PositionId posId, uint256 amountReceived, int256 profit
    );

    /**
     * @notice Emitted when a user validates the opening of a long position
     * @param user The user address
     * @param to The address that will be the owner of the position
     * @param totalExpo The total expo of the position
     * @param newStartPrice The asset price at the moment of the position creation (final)
     * @param posId The unique position identifier
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceUpdated` will be emitted too
     */
    event ValidatedOpenPosition(
        address indexed user, address indexed to, uint128 totalExpo, uint128 newStartPrice, PositionId posId
    );

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
    }

    /**
     * @notice Emitted when a user's position was liquidated while pending validation and we remove the pending action
     * @param user The user address
     * @param posId The unique position identifier
     */
    event StalePendingActionRemoved(address indexed user, PositionId posId);

    /**
     * @notice Emitted when a user validates a withdrawal
     * @param user The user address
     * @param to The address that received the assets
     * @param amountWithdrawn The amount of asset that were withdrawn
     * @param usdnBurned The amount of USDN that were burned
     * @param timestamp The timestamp of the InitiatedWithdrawal action
     */
    event ValidatedWithdrawal(
        address indexed user, address indexed to, uint256 amountWithdrawn, uint256 usdnBurned, uint256 timestamp
    );

    /**
     * @notice Emitted when a user validates a deposit
     * @param user The user address
     * @param to The address that received the USDN tokens
     * @param amountDeposited The amount of asset that were deposited
     * @param usdnMinted The amount of USDN that were minted
     * @param timestamp The timestamp of the InitiatedDeposit action
     */
    event ValidatedDeposit(
        address indexed user, address indexed to, uint256 amountDeposited, uint256 usdnMinted, uint256 timestamp
    );

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
     * @dev Structure to hold the transient data during `_validateOpenPosition`
     * @param action The long pending action
     * @param startPrice The new entry price of the position
     * @param tickHash The tick hash
     * @param pos The position object
     * @param liqPriceWithoutPenalty The new liquidation price without penalty
     * @param leverage The new leverage
     * @param liquidationPenalty The liquidation penalty for the position's tick
     */
    struct ValidateOpenPositionData {
        LongPendingAction action;
        uint128 startPrice;
        bytes32 tickHash;
        Position pos;
        uint128 liqPriceWithoutPenalty;
        uint128 leverage;
        uint8 liquidationPenalty;
    }

    /**
     * @notice Clear the user pending action and return it
     * @param user The user's address
     * @return action_ The cleared pending action struct
     */
    function _getAndClearPendingAction(Storage storage s, address user)
        external
        returns (PendingAction memory action_)
    {
        uint128 rawIndex;
        (action_, rawIndex) = _getPendingActionOrRevert(s, user);
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Get the pending action for a user
     * @dev This function reverts if there is no pending action for the user
     * @param user The user's address
     * @return action_ The pending action struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingActionOrRevert(Storage storage s, address user)
        public
        view
        returns (PendingAction memory action_, uint128 rawIndex_)
    {
        (action_, rawIndex_) = _getPendingAction(s, user);
        if (action_.action == ProtocolAction.None) {
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
    }

    /**
     * @notice Get the pending action for a user
     * @dev To check for the presence of a pending action, compare `action_.action` to `ProtocolAction.None`. There is
     * a pending action only if the action is different from `ProtocolAction.None`
     * @param user The user's address
     * @return action_ The pending action struct if any, otherwise a zero-initialized struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingAction(Storage storage s, address user)
        public
        view
        returns (PendingAction memory action_, uint128 rawIndex_)
    {
        uint256 pendingActionIndex = s._pendingActions[user];
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            // no pending action
            return (action_, rawIndex_);
        }

        rawIndex_ = uint128(pendingActionIndex - 1);
        action_ = s._pendingActionsQueue.atRaw(rawIndex_);
    }

    /**
     * @notice Add a pending action to the queue
     * @dev This reverts if there is already a pending action for this user
     * @param user The user's address
     * @param action The pending action struct
     * @return securityDepositValue_ The security deposit value of the stale pending action
     */
    function _addPendingAction(Storage storage s, address user, PendingAction memory action)
        external
        returns (uint256 securityDepositValue_)
    {
        securityDepositValue_ = _removeStalePendingAction(s, user); // check if there is a pending action that was
            // liquidated and remove it
        if (s._pendingActions[user] > 0) {
            revert IUsdnProtocolErrors.UsdnProtocolPendingAction();
        }
        // Add the action to the queue
        uint128 rawIndex = s._pendingActionsQueue.pushBack(action);
        // Store the index shifted by one, so that zero means no pending action
        s._pendingActions[user] = uint256(rawIndex) + 1;
    }

    /**
     * @notice Remove the pending action from the queue if its tick version doesn't match the current tick version
     * @dev This is only applicable to `ValidateOpenPosition` pending actions
     * @param user The user's address
     * @return securityDepositValue_ The security deposit value of the removed stale pending action
     */
    function _removeStalePendingAction(Storage storage s, address user)
        public
        returns (uint256 securityDepositValue_)
    {
        // slither-disable-next-line incorrect-equality
        if (s._pendingActions[user] == 0) {
            return 0;
        }
        (PendingAction memory action, uint128 rawIndex) = _getPendingAction(s, user);
        // the position is only at risk of being liquidated while pending if it is an open position action
        // slither-disable-next-line incorrect-equality
        if (action.action == ProtocolAction.ValidateOpenPosition) {
            LongPendingAction memory openAction = _toLongPendingAction(action);
            (, uint256 version) = commonLib._tickHash(s, openAction.tick);
            if (version != openAction.tickVersion) {
                securityDepositValue_ = openAction.securityDepositValue;
                // the position was liquidated while pending
                // remove the stale pending action
                s._pendingActionsQueue.clearAt(rawIndex);
                delete s._pendingActions[user];
                emit StalePendingActionRemoved(
                    user,
                    PositionId({ tick: openAction.tick, tickVersion: openAction.tickVersion, index: openAction.index })
                );
            }
        }
    }

    /**
     * @notice Update the state of the contract according to the liquidation effects
     * @param data The liquidation data
     * @param effects The effects of the liquidations
     * @return The updated liquidation data
     */
    function _updateStateAfterLiquidation(
        Storage storage s,
        LiquidationData memory data,
        LiquidationsEffects memory effects
    ) public returns (LiquidationData memory) {
        // update the state
        s._totalLongPositions -= effects.liquidatedPositions;
        s._totalExpo -= data.totalExpoToRemove;
        s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.sub(HugeUint.wrap(data.accumulatorValueToRemove));

        // keep track of the highest populated tick
        if (effects.liquidatedPositions != 0) {
            if (data.iTick < data.currentTick) {
                // all ticks above the current tick were liquidated
                s._highestPopulatedTick = commonLib._findHighestPopulatedTick(s, data.currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                s._highestPopulatedTick = commonLib._findHighestPopulatedTick(s, data.iTick);
            }
        }

        // Transfer remaining collateral to vault or pay bad debt
        data.tempLongBalance -= effects.remainingCollateral;
        data.tempVaultBalance += effects.remainingCollateral;

        return data;
    }

    /**
     * @notice Liquidate positions which have a liquidation price lower than the current price
     * @param currentPrice The current price of the asset
     * @param iteration The maximum number of ticks to liquidate (minimum is 1)
     * @param tempLongBalance The temporary long balance as calculated when applying PnL and funding
     * @param tempVaultBalance The temporary vault balance as calculated when applying PnL and funding
     * @return effects_ The effects of the liquidations on the protocol
     */
    function _liquidatePositions(
        Storage storage s,
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) external returns (LiquidationsEffects memory effects_) {
        int256 longTradingExpo = s._totalExpo.toInt256() - tempLongBalance;
        if (longTradingExpo <= 0) {
            // In case the long balance is equal to the total expo (or exceeds it), the trading expo will become
            // zero.
            // In this case, it's not possible to calculate the current tick, so we can't perform any liquidations.
            (effects_.newLongBalance, effects_.newVaultBalance) =
                commonLib._handleNegativeBalances(tempLongBalance, tempVaultBalance);
            return effects_;
        }

        LiquidationData memory data;
        data.tempLongBalance = tempLongBalance;
        data.tempVaultBalance = tempVaultBalance;
        data.longTradingExpo = uint256(longTradingExpo);
        data.currentPrice = currentPrice;
        data.accumulator = s._liqMultiplierAccumulator;

        // max iteration limit
        if (iteration > s.MAX_LIQUIDATION_ITERATION) {
            iteration = s.MAX_LIQUIDATION_ITERATION;
        }

        uint256 unadjustedPrice =
            commonLib._unadjustPrice(data.currentPrice, data.currentPrice, data.longTradingExpo, data.accumulator);
        data.currentTick = TickMath.getClosestTickAtPrice(unadjustedPrice);
        data.iTick = s._highestPopulatedTick;

        do {
            uint256 index = s._tickBitmap.findLastSet(commonLib._calcBitmapIndexFromTick(s, data.iTick));
            if (index == LibBitmap.NOT_FOUND) {
                // no populated ticks left
                break;
            }

            data.iTick = commonLib._calcTickFromBitmapIndex(s, index);
            if (data.iTick < data.currentTick) {
                // all ticks that can be liquidated have been processed
                break;
            }

            // we have found a non-empty tick that needs to be liquidated
            (bytes32 tickHash,) = commonLib._tickHash(s, data.iTick);

            TickData memory tickData = s._tickData[tickHash];
            // Update transient data
            data.totalExpoToRemove += tickData.totalExpo;
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.iTick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
            data.accumulatorValueToRemove += unadjustedTickPrice * tickData.totalExpo;
            // Update return values
            effects_.liquidatedPositions += tickData.totalPos;
            ++effects_.liquidatedTicks;
            int256 tickValue =
                commonLib._tickValue(s, data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator, tickData);
            effects_.remainingCollateral += tickValue;

            // Reset tick by incrementing the tick version
            ++s._tickVersion[data.iTick];
            // Update bitmap to reflect that the tick is empty
            s._tickBitmap.unset(index);

            emit LiquidatedTick(
                data.iTick,
                s._tickVersion[data.iTick] - 1,
                data.currentPrice,
                commonLib.getEffectivePriceForTick(
                    data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator
                ),
                tickValue
            );
        } while (effects_.liquidatedTicks < iteration);

        data = _updateStateAfterLiquidation(s, data, effects_);

        (effects_.newLongBalance, effects_.newVaultBalance) =
            commonLib._handleNegativeBalances(data.tempLongBalance, data.tempVaultBalance);
    }

    /**
     * @notice This is the mutating version of `getActionablePendingAction`, where empty items at the front of the list
     * are removed
     * @return action_ The first actionable pending action if any, otherwise a struct with all fields set to zero and
     * ProtocolAction.None
     * @return rawIndex_ The raw index in the queue for the returned pending action, or zero
     */
    function _getActionablePendingAction(Storage storage s)
        public
        returns (PendingAction memory action_, uint128 rawIndex_)
    {
        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (action_, rawIndex_);
        }
        uint256 maxIter = s.MAX_ACTIONABLE_PENDING_ACTIONS;
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        do {
            // since we will never call `front` more than `queueLength` times, there is no risk of reverting
            (PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.front();
            // gas optimization
            unchecked {
                i++;
            }
            if (candidate.timestamp == 0) {
                // remove the stale pending action
                // slither-disable-next-line unused-return
                s._pendingActionsQueue.popFront();
                // try the next one
                continue;
            } else if (candidate.timestamp + s._validationDeadline < block.timestamp) {
                // we found an actionable pending action
                return (candidate, rawIndex);
            }
            // the first pending action is not actionable
            return (action_, rawIndex_);
        } while (i < maxIter);
    }

    /**
     * @notice Clear the pending action for a user
     * @param user The user's address
     */
    function _clearPendingAction(Storage storage s, address user) public {
        uint256 pendingActionIndex = s._pendingActions[user];
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Convert a `PendingAction` to a `DepositPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted deposit pending action
     */
    function _toDepositPendingAction(PendingAction memory action)
        public
        pure
        returns (DepositPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `WithdrawalPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted withdrawal pending action
     */
    function _toWithdrawalPendingAction(PendingAction memory action)
        public
        pure
        returns (WithdrawalPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `LongPendingAction`
     * @param action An untyped pending action
     * @return longAction_ The converted long pending action
     */
    function _toLongPendingAction(PendingAction memory action)
        public
        pure
        returns (LongPendingAction memory longAction_)
    {
        assembly {
            longAction_ := action
        }
    }

    /**
     * @notice Convert a `DepositPendingAction` to a `PendingAction`
     * @param action A deposit pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertDepositPendingAction(DepositPendingAction memory action)
        external
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    function _validateDepositWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
    {
        DepositPendingAction memory deposit = _toDepositPendingAction(pending);

        PriceInfo memory currentPrice =
            commonLib._getOraclePrice(s, ProtocolAction.ValidateDeposit, deposit.timestamp, priceData);

        // adjust balances
        commonLib._applyPnlAndFundingAndLiquidate(
            s, currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, priceData
        );

        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.
        // Apply fees on price
        uint128 priceWithFees = (currentPrice.price - currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        uint256 usdnToMint1 = commonLib._calcMintUsdn(
            s, deposit.amount, deposit.balanceVault, deposit.usdnTotalSupply, deposit.assetPrice
        );

        uint256 usdnToMint2 = commonLib._calcMintUsdn(
            s,
            deposit.amount,
            // Calculate the available balance in the vault side if the price moves to `priceWithFees`
            commonLib._vaultAssetAvailable(
                deposit.totalExpo, deposit.balanceVault, deposit.balanceLong, priceWithFees, deposit.assetPrice
            ).toUint256(),
            deposit.usdnTotalSupply,
            priceWithFees
        );

        uint256 usdnToMint;
        // We use the lower of the two amounts to mint
        if (usdnToMint1 <= usdnToMint2) {
            usdnToMint = usdnToMint1;
        } else {
            usdnToMint = usdnToMint2;
        }

        s._balanceVault += deposit.amount;

        s._usdn.mint(deposit.to, usdnToMint);
        emit ValidatedDeposit(deposit.user, deposit.to, deposit.amount, usdnToMint, deposit.timestamp);
    }

    /**
     * @notice Update protocol balances, then prepare the data for the validate open position action.
     * @param pending The pending action data
     * @param priceData The current price data
     * @return data_ The validate open position data struct
     * @return liq_ Whether the position was liquidated and the caller should return early
     */
    function _prepareValidateOpenPositionData(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
        returns (ValidateOpenPositionData memory data_, bool liq_)
    {
        data_.action = _toLongPendingAction(pending);
        PriceInfo memory currentPrice =
            commonLib._getOraclePrice(s, ProtocolAction.ValidateOpenPosition, data_.action.timestamp, priceData);
        // Apply fees on price
        data_.startPrice = (currentPrice.price + currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        commonLib._applyPnlAndFundingAndLiquidate(
            s, currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, priceData
        );

        uint256 version;
        (data_.tickHash, version) = commonLib._tickHash(s, data_.action.tick);
        if (version != data_.action.tickVersion) {
            // The current tick version doesn't match the version from the pending action.
            // This means the position has been liquidated in the mean time
            emit StalePendingActionRemoved(
                data_.action.user,
                PositionId({ tick: data_.action.tick, tickVersion: data_.action.tickVersion, index: data_.action.index })
            );
            return (data_, true);
        }
        // Get the position
        data_.pos = s._longPositions[data_.tickHash][data_.action.index];
        // Re-calculate leverage
        data_.liquidationPenalty = s._tickData[data_.tickHash].liquidationPenalty;
        data_.liqPriceWithoutPenalty = commonLib.getEffectivePriceForTick(
            s, commonLib._calcTickWithoutPenalty(s, data_.action.tick, data_.liquidationPenalty)
        );
        // reverts if liqPriceWithoutPenalty >= startPrice
        data_.leverage = commonLib._getLeverage(s, data_.startPrice, data_.liqPriceWithoutPenalty);
    }

    /**
     * @notice Execute the first actionable pending action or revert if the price data was not provided.
     * @param data The price data and raw indices
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingActionOrRevert(Storage storage s, PreviousActionsData calldata data)
        external
        returns (uint256 securityDepositValue_)
    {
        bool success;
        (success,, securityDepositValue_) = _executePendingAction(s, data);
        if (!success) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingActionData();
        }
    }

    /**
     * @notice Execute the first actionable pending action and report success.
     * @param data The price data and raw indices
     * @return success_ Whether the price data is valid
     * @return executed_ Whether the pending action was executed (false if the queue has no actionable item)
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingAction(Storage storage s, PreviousActionsData calldata data)
        public
        returns (bool success_, bool executed_, uint256 securityDepositValue_)
    {
        (PendingAction memory pending, uint128 rawIndex) = _getActionablePendingAction(s);
        if (pending.action == ProtocolAction.None) {
            // no pending action
            return (true, false, 0);
        }
        uint256 length = data.priceData.length;
        if (data.rawIndices.length != length || length < 1) {
            return (false, false, 0);
        }
        uint128 offset;
        unchecked {
            // underflow is desired here (wrap-around)
            offset = rawIndex - data.rawIndices[0];
        }
        if (offset >= length || data.rawIndices[offset] != rawIndex) {
            return (false, false, 0);
        }
        bytes calldata priceData = data.priceData[offset];
        _clearPendingAction(s, pending.user);
        if (pending.action == ProtocolAction.ValidateDeposit) {
            _validateDepositWithAction(s, pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateWithdrawal) {
            _validateWithdrawalWithAction(s, pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateOpenPosition) {
            _validateOpenPositionWithAction(s, pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateClosePosition) {
            _validateClosePositionWithAction(s, pending, priceData);
        }
        success_ = true;
        executed_ = true;
        securityDepositValue_ = pending.securityDepositValue;
        emit SecurityDepositRefunded(pending.user, msg.sender, securityDepositValue_);
    }

    function _validateWithdrawalWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
    {
        WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice =
            commonLib._getOraclePrice(s, ProtocolAction.ValidateWithdrawal, withdrawal.timestamp, priceData);

        commonLib._applyPnlAndFundingAndLiquidate(
            s, currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, priceData
        );

        // Apply fees on price
        uint128 withdrawalPriceWithFees =
            (currentPrice.price + currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.
        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = commonLib._vaultAssetAvailable(
            withdrawal.totalExpo,
            withdrawal.balanceVault,
            withdrawal.balanceLong,
            withdrawalPriceWithFees,
            withdrawal.assetPrice
        ).toUint256();
        uint256 available;
        if (available1 <= available2) {
            available = available1;
        } else {
            available = available2;
        }

        uint256 shares = commonLib._mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);

        // we have the USDN in the contract already
        IUsdn usdn = s._usdn;

        uint256 assetToTransfer = commonLib._calcBurnUsdn(shares, available, usdn.totalShares());

        usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransfer > 0) {
            s._balanceVault -= assetToTransfer;
            s._asset.safeTransfer(withdrawal.to, assetToTransfer);
        }

        emit ValidatedWithdrawal(
            withdrawal.user, withdrawal.to, assetToTransfer, usdn.convertToTokens(shares), withdrawal.timestamp
        );
    }

    struct ValidateClosePositionWithActionData {
        LongPendingAction long;
        PriceInfo currentPrice;
        uint128 priceWithFees;
        uint128 liquidationPrice;
        uint128 liqPriceWithoutPenalty;
    }

    function _validateClosePositionWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
    {
        ValidateClosePositionWithActionData memory data;

        data.long = _toLongPendingAction(pending);

        data.currentPrice =
            commonLib._getOraclePrice(s, ProtocolAction.ValidateClosePosition, data.long.timestamp, priceData);

        commonLib._applyPnlAndFundingAndLiquidate(
            s, data.currentPrice.neutralPrice, data.currentPrice.timestamp, s._liquidationIteration, false, priceData
        );

        // Apply fees on price
        data.priceWithFees =
            (data.currentPrice.price - data.currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        // get liquidation price (with liq penalty) to check if position was valid at `timestamp + validationDelay`
        data.liquidationPrice = commonLib._getEffectivePriceForTick(s, data.long.tick, data.long.closeLiqMultiplier);

        if (data.currentPrice.neutralPrice <= data.liquidationPrice) {
            // Position should be liquidated, we don't transfer assets to the user.
            // Position was already removed from tick so no additional bookkeeping is necessary.
            // Credit the full amount to the vault to preserve the total balance invariant.
            s._balanceVault += data.long.closeBoundedPositionValue;
            emit LiquidatedPosition(
                data.long.user,
                PositionId({ tick: data.long.tick, tickVersion: data.long.tickVersion, index: data.long.index }),
                data.currentPrice.neutralPrice,
                data.liquidationPrice
            );
            return;
        }

        data.liqPriceWithoutPenalty = commonLib._getEffectivePriceForTick(
            s,
            commonLib._calcTickWithoutPenalty(s, data.long.tick, commonLib.getTickLiquidationPenalty(s, data.long.tick)),
            data.long.closeLiqMultiplier
        );

        int256 positionValue =
            commonLib._positionValue(data.priceWithFees, data.liqPriceWithoutPenalty, data.long.closePosTotalExpo);

        uint256 assetToTransfer;
        if (positionValue > 0) {
            assetToTransfer = uint256(positionValue);
            // Normally, the position value should be smaller than `long.closeBoundedPositionValue` (due to the position
            // fee).
            // We can send the difference (any remaining collateral) to the vault.
            // If the price increased since the initiate, it's possible that the position value is higher than the
            // `long.closeBoundedPositionValue`. In that case, we need to take the missing assets from the vault.
            if (assetToTransfer < data.long.closeBoundedPositionValue) {
                uint256 remainingCollateral;
                unchecked {
                    // since assetToTransfer is strictly smaller than closeBoundedPositionValue, this operation can't
                    // underflow
                    remainingCollateral = data.long.closeBoundedPositionValue - assetToTransfer;
                }
                s._balanceVault += remainingCollateral;
            } else if (assetToTransfer > data.long.closeBoundedPositionValue) {
                uint256 missingValue;
                unchecked {
                    // since assetToTransfer is strictly larger than closeBoundedPositionValue, this operation can't
                    // underflow
                    missingValue = assetToTransfer - data.long.closeBoundedPositionValue;
                }
                uint256 balanceVault = s._balanceVault;
                // If the vault does not have enough balance left to pay out the missing value, we take what we can
                if (missingValue > balanceVault) {
                    s._balanceVault = 0;
                    unchecked {
                        // since missingValue is strictly larger than balanceVault, their subtraction can't underflow
                        // moreover, since (missingValue - balanceVault) is smaller than or equal to missingValue,
                        // and since missingValue is smaller than or equal to assetToTransfer,
                        // (missingValue - balanceVault) is smaller than or equal to assetToTransfer, and their
                        // subtraction can't underflow.
                        assetToTransfer -= missingValue - balanceVault;
                    }
                } else {
                    unchecked {
                        // since missingValue is smaller than or equal to balanceVault, this operation can't underflow
                        s._balanceVault = balanceVault - missingValue;
                    }
                }
            }
        }
        // in case the position value is zero or negative, we don't transfer any asset to the user

        // send the asset to the user
        if (assetToTransfer > 0) {
            s._asset.safeTransfer(data.long.to, assetToTransfer);
        }

        emit ValidatedClosePosition(
            data.long.user,
            data.long.to,
            PositionId({ tick: data.long.tick, tickVersion: data.long.tickVersion, index: data.long.index }),
            assetToTransfer,
            assetToTransfer.toInt256() - commonLib._toInt256(data.long.closeAmount)
        );
    }

    /**
     * @notice Validate an open position action.
     * @param pending The pending action data
     * @param priceData The current price data
     */
    function _validateOpenPositionWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        public
    {
        (ValidateOpenPositionData memory data, bool liquidated) =
            _prepareValidateOpenPositionData(s, pending, priceData);
        if (liquidated) {
            return;
        }

        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        // However, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        uint128 maxLeverage = uint128(s._maxLeverage);
        if (data.leverage > maxLeverage) {
            // theoretical liquidation price for _maxLeverage
            data.liqPriceWithoutPenalty = commonLib._getLiquidationPrice(s, data.startPrice, maxLeverage);
            // adjust to closest valid tick down
            int24 tickWithoutPenalty = commonLib.getEffectiveTickForPrice(s, data.liqPriceWithoutPenalty);

            // apply liquidation penalty with the current penalty setting
            uint8 currentLiqPenalty = s._liquidationPenalty;
            PositionId memory newPosId;
            newPosId.tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * s._tickSpacing;
            // retrieve the actual penalty for this tick we want to use
            uint8 liquidationPenalty = commonLib.getTickLiquidationPenalty(s, newPosId.tick);
            // check if the penalty for that tick is different from the current setting
            if (liquidationPenalty == currentLiqPenalty) {
                // Since the tick's penalty is the same as what we assumed, we can use the `tickWithoutPenalty` from
                // above.
                // Retrieve exact liquidation price without penalty
                data.liqPriceWithoutPenalty = commonLib.getEffectivePriceForTick(s, tickWithoutPenalty);
            } else {
                // The tick's imposed penalty is different from the current setting, so the `tickWithoutPenalty` we
                // calculated above can't be used to calculate the leverage.
                // We must instead use the tick's penalty to find the new `liqPriceWithoutPenalty` and calculate the
                // leverage.

                // Note: In case the tick liquidation penalty is lower than the current setting, it might lead to a
                // leverage that exceeds the max leverage slightly. We allow this behavior in this rare occurrence.

                // Retrieve exact liquidation price without penalty.
                data.liqPriceWithoutPenalty = commonLib.getEffectivePriceForTick(
                    s, commonLib._calcTickWithoutPenalty(s, newPosId.tick, liquidationPenalty)
                );
            }

            // move the position to its new tick, updating its total expo, and returning the new tickVersion and index
            // remove position from old tick completely
            commonLib._removeAmountFromPosition(
                s, data.action.tick, data.action.index, data.pos, data.pos.amount, data.pos.totalExpo
            );
            // update position total expo (because of new leverage / liq price)
            data.pos.totalExpo =
                commonLib._calculatePositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);
            // insert position into new tick
            (newPosId.tickVersion, newPosId.index) =
                commonLib._saveNewPosition(s, newPosId.tick, data.pos, liquidationPenalty);
            // no long balance update is necessary (collateral didn't change)

            // emit LiquidationPriceUpdated
            emit LiquidationPriceUpdated(
                PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index }),
                newPosId
            );
            emit ValidatedOpenPosition(data.action.user, data.action.to, data.pos.totalExpo, data.startPrice, newPosId);
            return;
        }

        // Calculate the new total expo
        uint128 expoBefore = data.pos.totalExpo;
        uint128 expoAfter =
            commonLib._calculatePositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);

        // Update the total expo of the position
        s._longPositions[data.tickHash][data.action.index].totalExpo = expoAfter;
        // Update the total expo by adding the position's new expo and removing the old one.
        // Do not use += or it will underflow
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

        emit ValidatedOpenPosition(
            data.action.user,
            data.action.to,
            expoAfter,
            data.startPrice,
            PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index })
        );
    }
}
