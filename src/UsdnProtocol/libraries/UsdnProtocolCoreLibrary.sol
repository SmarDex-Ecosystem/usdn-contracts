// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Accumulator, HugeUint } from "../../libraries/Accumulator.sol";
import { DoubleEndedQueue } from "../../libraries/DoubleEndedQueue.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolCoreLibrary {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using Accumulator for HugeUint.Uint512;
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeTransferLib for address;
    using SignedMath for int256;

    /// @notice See {IUsdnProtocolCore.initialize}.
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external {
        Types.Storage storage s = Utils._getMainStorage();

        // since all USDN must be minted by the protocol, we check that the total supply is 0
        IUsdn usdn = s._usdn;
        if (usdn.totalSupply() != 0) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdn(address(usdn));
        }

        PriceInfo memory currentPrice =
            Utils._getOraclePrice(Types.ProtocolAction.Initialize, block.timestamp, "", currentPriceData);

        s._lastUpdateTimestamp = uint128(block.timestamp);
        s._lastPrice = currentPrice.price.toUint128();

        (int24 tickWithPenalty, uint128 liqPriceWithoutPenalty) =
            Long._getTickFromDesiredLiqPrice(desiredLiqPrice, s._liquidationPenalty);

        _checkOpenPositionLeverage(currentPrice.price.toUint128(), liqPriceWithoutPenalty, s._maxLeverage);

        uint128 positionTotalExpo =
            Utils._calcPositionTotalExpo(longAmount, currentPrice.price.toUint128(), liqPriceWithoutPenalty);

        _checkInitImbalance(positionTotalExpo, longAmount, depositAmount);

        _createInitialDeposit(depositAmount, currentPrice.price.toUint128());

        _createInitialPosition(longAmount, currentPrice.price.toUint128(), tickWithPenalty, positionTotalExpo);

        Utils._refundEther(address(this).balance, payable(msg.sender));
    }

    /// @notice See {IUsdnProtocolFallback.removeBlockedPendingAction(address,address payable)}.
    function removeBlockedPendingAction(address validator, address payable to) external {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 pendingActionIndex = s._pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        _removeBlockedPendingAction(rawIndex, to, true);
    }

    /// @notice See {IUsdnProtocolFallback.removeBlockedPendingActionNoCleanup(address,address payable)}.
    function removeBlockedPendingActionNoCleanup(address validator, address payable to) external {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 pendingActionIndex = s._pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        _removeBlockedPendingAction(rawIndex, to, false);
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
    ) external returns (uint256 amountToRefund_) {
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
        amountToRefund_ = _addPendingAction(validator, Utils._convertLongPendingAction(action));
    }

    /**
     * @notice Prepares the pending action struct for a withdrawal and adds it to the queue.
     * @param to The recipient of the assets.
     * @param validator The address that is supposed to validate the withdrawal and receive the security deposit.
     * @param usdnShares The amount of USDN shares to burn.
     * @param securityDepositValue The value of the security deposit for the newly created pending action.
     * @param data The withdrawal action data.
     * @return amountToRefund_ Refund The security deposit value of a stale pending action.
     */
    function _createWithdrawalPendingAction(
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        Vault.WithdrawalData memory data
    ) external returns (uint256 amountToRefund_) {
        Types.PendingAction memory action = Utils._convertWithdrawalPendingAction(
            Types.WithdrawalPendingAction({
                action: Types.ProtocolAction.ValidateWithdrawal,
                timestamp: uint40(block.timestamp),
                feeBps: data.feeBps,
                to: to,
                validator: validator,
                securityDepositValue: securityDepositValue,
                sharesLSB: Vault._calcWithdrawalAmountLSB(usdnShares),
                sharesMSB: Vault._calcWithdrawalAmountMSB(usdnShares),
                assetPrice: data.lastPrice,
                totalExpo: data.totalExpo,
                balanceVault: data.balanceVault,
                balanceLong: data.balanceLong,
                usdnTotalShares: data.usdnTotalShares
            })
        );
        amountToRefund_ = _addPendingAction(validator, action);
    }

    /// @notice See {IUsdnProtocolFallback.getUserPendingAction}.
    function getUserPendingAction(address validator) external view returns (Types.PendingAction memory action_) {
        (action_,) = _getPendingAction(validator);
    }

    /// @notice See {IUsdnProtocolCore.funding}.
    function funding(uint128 timestamp)
        external
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        (funding_, fundingPerDay_, oldLongExpo_) = _funding(timestamp, s._EMA);
    }

    /**
     * @notice Gets the predicted value of the long balance for the given asset price and timestamp.
     * @dev The effects of the funding and any PnL of the long positions since the last contract state
     * update is taken into account, as well as the fees. If the provided timestamp is older than the last state
     * update, the function reverts with `UsdnProtocolTimestampTooOld`. The value cannot be below 0.
     * @param currentPrice The given asset price.
     * @param timestamp The timestamp corresponding to the given price.
     * @return available_ The long balance value in assets.
     * @return fee_ The protocol fees in asset units, either positive or negative.
     */
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (uint256 available_, int256 fee_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }

        (int256 fundAsset,) = _fundingAsset(timestamp, s._EMA);
        fee_ = fundAsset * Utils._toInt256(s._protocolFeeBps) / int256(Constants.BPS_DIVISOR);

        int256 tempAvailable;
        if (fundAsset > 0) {
            tempAvailable = Utils._longAssetAvailable(currentPrice).safeSub(fundAsset);
        } else {
            // fees have the same sign as fundAsset (negative here), so we need to sub them
            tempAvailable = Utils._longAssetAvailable(currentPrice).safeSub(fundAsset - fee_);
        }

        // clamp the value to 0
        if (tempAvailable > 0) {
            // cast is safe as tempAvailable cannot be below 0
            available_ = uint256(tempAvailable);
        }

        uint256 maxLongBalance = _calcMaxLongBalance(s._totalExpo);
        if (available_ > maxLongBalance) {
            available_ = maxLongBalance;
        }

        uint256 totalBalance = s._balanceLong + s._balanceVault - FixedPointMathLib.abs(fee_);
        if (available_ > totalBalance) {
            available_ = totalBalance;
        }
    }

    /// @notice See {IUsdnProtocolLong.longTradingExpoWithFunding}.
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public view returns (uint256 expo_) {
        Types.Storage storage s = Utils._getMainStorage();

        (uint256 available,) = longAssetAvailableWithFunding(currentPrice, timestamp);

        expo_ = s._totalExpo - available;
    }

    /**
     * @notice Checks if the position's leverage is in the authorized range of values.
     * @param adjustedPrice The adjusted price of the asset.
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty.
     * @param userMaxLeverage The maximum leverage allowed by the user for the newly created position.
     */
    function _checkOpenPositionLeverage(uint128 adjustedPrice, uint128 liqPriceWithoutPenalty, uint256 userMaxLeverage)
        public
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
     * @notice Prepares the pending action struct for an open position and adds it to the queue.
     * @param to The address that will be the owner of the position.
     * @param validator The address which is supposed to validate the position and receive the
     * security deposit.
     * @param securityDepositValue The value of the security deposit for the newly created pending action.
     * @param data The open position action data.
     * @return amountToRefund_ The security deposit value of a stale pending action, if any was removed.
     */
    function _createOpenPendingAction(
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
        amountToRefund_ = _addPendingAction(validator, Utils._convertLongPendingAction(action));
    }

    /**
     * @notice Computes the profits and losses on the long side, calculates the funding, applies protocol fees,
     * updates the liquidation multiplier and determines the temporary new balances for each side.
     * @dev This function updates the state of `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding`, but does not
     * update the balances. This is left to the caller.
     * @param currentPrice The current price.
     * @param timestamp The timestamp of the current price.
     * @return data_ The data containing the temporary long balance, the temporary vault
     * balance, the last price and a flag indicating if the price is recent.
     */
    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        public
        returns (Types.ApplyPnlAndFundingData memory data_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        int256 fundAsset;
        {
            // cache variable for optimization
            uint128 lastUpdateTimestamp = s._lastUpdateTimestamp;
            // if the price is not fresh, do nothing
            if (timestamp <= lastUpdateTimestamp) {
                return Types.ApplyPnlAndFundingData({
                    tempLongBalance: s._balanceLong.toInt256(),
                    tempVaultBalance: s._balanceVault.toInt256(),
                    lastPrice: s._lastPrice
                });
            }

            // calculate the funding
            int256 fundingPerDay;
            (fundAsset, fundingPerDay) = _fundingAsset(timestamp, s._EMA);

            s._lastFundingPerDay = fundingPerDay;
            emit IUsdnProtocolEvents.LastFundingPerDayUpdated(fundingPerDay, timestamp);

            // update the funding EMA (mutates the storage)
            _updateEMA(fundingPerDay, timestamp - lastUpdateTimestamp);
        }

        // take protocol fee on the funding value
        (int256 fee, int256 fundAssetWithFee) = _calculateFee(fundAsset);

        // we subtract the fee from the total balance
        int256 totalBalance = (s._balanceLong + s._balanceVault).toInt256() - fee;

        // calculate new balances (for now, any bad debt has not been repaid, balances could become negative)
        if (fundAsset > 0) {
            // in case of positive funding, the long balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the vault balance will be incremented
            // only by the funding amount minus the fee amount
            data_.tempLongBalance = Utils._longAssetAvailable(currentPrice).safeSub(fundAsset);
        } else {
            // in case of negative funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the long balance will be incremented
            // only by the funding amount minus the fee amount
            data_.tempLongBalance = Utils._longAssetAvailable(currentPrice).safeSub(fundAssetWithFee);
        }

        uint256 maxLongBalance = _calcMaxLongBalance(s._totalExpo);
        if (data_.tempLongBalance > 0 && uint256(data_.tempLongBalance) > maxLongBalance) {
            data_.tempLongBalance = maxLongBalance.toInt256();
        }

        data_.tempVaultBalance = totalBalance.safeSub(data_.tempLongBalance);

        // update state variables
        s._lastPrice = currentPrice;
        data_.lastPrice = currentPrice;
        s._lastUpdateTimestamp = timestamp;
    }

    /**
     * @notice Removes the pending action from the queue if its tick version doesn't match the current tick version,
     * indicating that the tick was liquidated.
     * @dev This is only applicable to `ValidateOpenPosition` pending actions.
     * @param validator The address associated with the pending action.
     * @return securityDepositValue_ The security deposit value of the removed stale pending action.
     */
    function _removeStalePendingAction(address validator) public returns (uint256 securityDepositValue_) {
        Types.Storage storage s = Utils._getMainStorage();

        if (s._pendingActions[validator] == 0) {
            return 0;
        }
        (Types.PendingAction memory action, uint128 rawIndex) = _getPendingAction(validator);
        // the position is only at risk of being liquidated while pending if it is an open position action
        if (action.action == Types.ProtocolAction.ValidateOpenPosition) {
            Types.LongPendingAction memory openAction = Utils._toLongPendingAction(action);
            uint256 version = s._tickVersion[openAction.tick];
            if (version != openAction.tickVersion) {
                securityDepositValue_ = openAction.securityDepositValue;
                // the position was liquidated while pending
                // remove the stale pending action
                s._pendingActionsQueue.clearAt(rawIndex);
                delete s._pendingActions[validator];
                emit IUsdnProtocolEvents.StalePendingActionRemoved(
                    validator,
                    Types.PositionId({
                        tick: openAction.tick,
                        tickVersion: openAction.tickVersion,
                        index: openAction.index
                    })
                );
            }
        }
    }

    /**
     * @notice Adds a pending action to the queue and removes a possible stale pending action.
     * @dev Reverts if there is already a pending action for this user.
     * @param validator The address which is supposed to validate the position and receive the
     * security deposit.
     * @param action The pending action struct.
     * @return amountToRefund_ The security deposit value of a stale pending action, if any was removed.
     */
    function _addPendingAction(address validator, Types.PendingAction memory action)
        public
        returns (uint256 amountToRefund_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        // check if there is a pending action that was liquidated and remove it
        amountToRefund_ = _removeStalePendingAction(validator);
        if (s._pendingActions[validator] > 0) {
            revert IUsdnProtocolErrors.UsdnProtocolPendingAction();
        }
        // add the action to the queue
        uint128 rawIndex = s._pendingActionsQueue.pushBack(action);
        // store the index shifted by one, so that zero means no pending action
        s._pendingActions[validator] = uint256(rawIndex) + 1;
    }

    /**
     * @notice Removes a blocked pending action and performs the minimal amount of cleanup necessary.
     * @dev This function should only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something reverting unexpectedly.
     * From the user action timestamp, the caller must wait at least `REMOVE_BLOCKED_PENDING_ACTIONS_DELAY` after both
     * `_lowLatencyValidatorDeadline` and `_onChainValidatorDeadline`.
     * @param rawIndex The raw index of the pending action in the queue.
     * @param to The recipient of the funds, which may include security deposit, assets and USDN tokens.
     * @param cleanup If `true`, will attempt to perform more cleanup at the risk of reverting. Always try `true` first.
     */
    function _removeBlockedPendingAction(uint128 rawIndex, address payable to, bool cleanup) public {
        Types.Storage storage s = Utils._getMainStorage();

        Types.PendingAction memory pending = s._pendingActionsQueue.atRaw(rawIndex);
        if (
            block.timestamp
                < pending.timestamp + s._lowLatencyValidatorDeadline + s._onChainValidatorDeadline
                    + Constants.REMOVE_BLOCKED_PENDING_ACTIONS_DELAY
        ) {
            revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
        }

        delete s._pendingActions[pending.validator];
        s._pendingActionsQueue.clearAt(rawIndex);
        if (pending.action == Types.ProtocolAction.ValidateDeposit && cleanup) {
            // for pending deposits, we send back the locked assets
            Types.DepositPendingAction memory deposit = Utils._toDepositPendingAction(pending);
            s._pendingBalanceVault -= Utils._toInt256(deposit.amount);
            address(s._asset).safeTransfer(to, deposit.amount);
        } else if (pending.action == Types.ProtocolAction.ValidateWithdrawal && cleanup) {
            // for pending withdrawals, we send the locked USDN
            Types.WithdrawalPendingAction memory withdrawal = Utils._toWithdrawalPendingAction(pending);
            uint256 shares = Utils._mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);
            // calculate the pending amount after fees to update the pending vault balance
            uint256 pendingAmountAfterFees = Utils._calcAmountToWithdraw(
                shares, withdrawal.balanceVault, withdrawal.usdnTotalShares, withdrawal.feeBps
            );
            s._pendingBalanceVault += pendingAmountAfterFees.toInt256();
            s._usdn.transferShares(to, shares);
        } else if (pending.action == Types.ProtocolAction.ValidateOpenPosition) {
            // for pending opens, we need to remove the position
            Types.LongPendingAction memory open = Utils._toLongPendingAction(pending);
            (bytes32 tHash, uint256 tickVersion) = Utils._tickHash(open.tick);
            if (tickVersion == open.tickVersion) {
                // we only need to modify storage if the pos was not liquidated already

                int256 posValue;
                if (cleanup) {
                    posValue = Long.getPositionValue(
                        Types.PositionId(open.tick, open.tickVersion, open.index), s._lastPrice, s._lastUpdateTimestamp
                    );
                }

                // safe cleanup operations
                Types.Position[] storage tickArray = s._longPositions[tHash];
                Types.Position memory pos = tickArray[open.index];
                delete s._longPositions[tHash][open.index];

                // more cleanup operations
                if (cleanup) {
                    Types.TickData storage tickData = s._tickData[tHash];
                    --s._totalLongPositions;
                    tickData.totalPos -= 1;
                    uint256 unadjustedTickPrice =
                        TickMath.getPriceAtTick(Utils._calcTickWithoutPenalty(open.tick, tickData.liquidationPenalty));
                    if (tickData.totalPos == 0) {
                        // we removed the last position in the tick
                        s._tickBitmap.unset(Utils._calcBitmapIndexFromTick(open.tick));
                        // reset tick penalty
                        tickData.liquidationPenalty = 0;
                    }
                    s._totalExpo -= pos.totalExpo;
                    tickData.totalExpo -= pos.totalExpo;
                    s._liqMultiplierAccumulator =
                        s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * pos.totalExpo));
                    if (posValue > 0) {
                        s._balanceLong -= uint256(posValue);
                        address(s._asset).safeTransfer(to, uint256(posValue));
                    } else if (posValue < 0) {
                        s._balanceLong += uint256(-posValue);
                        s._balanceVault -= uint256(-posValue);
                    }
                }
            }
        } else if (pending.action == Types.ProtocolAction.ValidateClosePosition && cleanup) {
            // for pending closes, the position is already out of the protocol
            Types.LongPendingAction memory close = Utils._toLongPendingAction(pending);
            // send the value of the position at the time of the initiate to the `to` address
            address(s._asset).safeTransfer(to, close.closeBoundedPositionValue);
            // as the assets were already removed from the long's balance, there are no additional steps needed
        }

        // we retrieve the security deposit
        if (cleanup) {
            (bool success,) = to.call{ value: pending.securityDepositValue }("");
            if (!success) {
                revert IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed();
            }
        }
    }

    /**
     * @notice Saves a new long position in the protocol, adjusting the tick data and global variables.
     * @dev This method does not update the long balance.
     * @param tick The tick to hold the new position.
     * @param long The position to save.
     * @param liquidationPenalty The liquidation penalty for the tick.
     * @return tickVersion_ The version of the tick.
     * @return index_ The index of the position in the tick array.
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator.
     */
    function _saveNewPosition(int24 tick, Types.Position memory long, uint24 liquidationPenalty)
        public
        returns (uint256 tickVersion_, uint256 index_, HugeUint.Uint512 memory liqMultiplierAccumulator_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        bytes32 tickHash;
        (tickHash, tickVersion_) = Utils._tickHash(tick);

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
            s._tickBitmap.set(Utils._calcBitmapIndexFromTick(tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
            unadjustedTickPrice = TickMath.getPriceAtTick(Utils._calcTickWithoutPenalty(tick, liquidationPenalty));
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's `liquidationPenalty` since it remains constant
            unadjustedTickPrice =
                TickMath.getPriceAtTick(Utils._calcTickWithoutPenalty(tick, tickData.liquidationPenalty));
        }
        // update the accumulator with the correct tick price (depending on the liquidation penalty value)
        liqMultiplierAccumulator_ = s._liqMultiplierAccumulator.add(HugeUint.wrap(unadjustedTickPrice * long.totalExpo));
        s._liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /**
     * @notice Gets the pending action for a validator.
     * @dev Reverts if there is no pending action for the validator.
     * @param validator The address which is supposed to validate the position and receive the
     * security deposit.
     * @return action_ The pending action struct.
     * @return rawIndex_ The raw index of the pending action in the queue.
     */
    function _getPendingActionOrRevert(address validator)
        public
        view
        returns (Types.PendingAction memory action_, uint128 rawIndex_)
    {
        (action_, rawIndex_) = _getPendingAction(validator);
        if (action_.action == Types.ProtocolAction.None) {
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
    }

    /**
     * @notice Gets the predicted value of the funding (in asset units) since the last state update for the given
     * timestamp.
     * @dev If the provided timestamp is older than the last state update, the result will be zero.
     * @param timestamp The targeted timestamp.
     * @param ema The EMA of the funding rate.
     * @return fundingAsset_ The number of asset tokens of funding (with asset decimals).
     * @return fundingPerDay_ The funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals.
     */
    function _fundingAsset(uint128 timestamp, int256 ema)
        internal
        view
        returns (int256 fundingAsset_, int256 fundingPerDay_)
    {
        int256 oldLongExpo;
        int256 fund;
        (fund, fundingPerDay_, oldLongExpo) = _funding(timestamp, ema);
        fundingAsset_ = fund.safeMul(oldLongExpo) / int256(10) ** Constants.FUNDING_RATE_DECIMALS;
    }

    /**
     * @notice Updates the Exponential Moving Average (EMA) of the funding rate (per day).
     * @dev This function is called every time the protocol state is updated.
     * All required checks are done in the caller function {_applyPnlAndFunding}.
     * If the number of seconds elapsed is greater than or equal to the EMA period, the EMA is updated to the last
     * funding value.
     * @param fundingPerDay The funding rate per day that was just calculated for the elapsed period.
     * @param secondsElapsed The number of seconds elapsed since the last protocol action.
     */
    function _updateEMA(int256 fundingPerDay, uint128 secondsElapsed) internal {
        Types.Storage storage s = Utils._getMainStorage();

        s._EMA = _calcEMA(fundingPerDay, secondsElapsed, s._EMAPeriod, s._EMA);
    }

    /**
     * @notice Calculates the protocol fee and apply it to the funding asset amount.
     * @dev The funding factor is only adjusted by the fee rate when the funding is negative (vault pays to the long
     * side).
     * @param fundAsset The funding asset amount to be used for the fee calculation.
     * @return fee_ The absolute value of the calculated fee.
     * @return fundAssetWithFee_ The updated funding asset amount after applying the fee.
     */
    function _calculateFee(int256 fundAsset) internal returns (int256 fee_, int256 fundAssetWithFee_) {
        Types.Storage storage s = Utils._getMainStorage();

        int256 protocolFeeBps = Utils._toInt256(s._protocolFeeBps);
        fee_ = fundAsset * protocolFeeBps / int256(Constants.BPS_DIVISOR);
        // fundAsset and fee_ have the same sign, we can safely subtract them to reduce the absolute amount of asset
        fundAssetWithFee_ = fundAsset - fee_;

        if (fee_ < 0) {
            // we want to return the absolute value of the fee
            fee_ = -fee_;
        }

        s._pendingProtocolFee += uint256(fee_);
    }

    /**
     * @notice Creates the initial deposit.
     * @dev To be called from `initialize`.
     * @param amount The initial deposit amount.
     * @param price The current asset price.
     */
    function _createInitialDeposit(uint128 amount, uint128 price) internal {
        Types.Storage storage s = Utils._getMainStorage();

        // transfer the assets for the deposit
        address(s._asset).safeTransferFrom(msg.sender, address(this), amount);

        s._balanceVault += amount;
        emit IUsdnProtocolEvents.InitiatedDeposit(msg.sender, msg.sender, amount, 0, block.timestamp, 0);

        // calculate the total minted amount of USDN shares (vault balance and total supply are zero for now, we assume
        // the USDN price to be $1 per token)
        // the decimals conversion here is necessary since we calculate an amount in tokens and we want the
        // corresponding amount of shares
        uint256 usdnSharesToMint = s._usdn.convertToShares(
            FixedPointMathLib.fullMulDiv(
                amount, price, 10 ** (s._assetDecimals + s._priceFeedDecimals - Constants.TOKENS_DECIMALS)
            )
        );
        IUsdn usdn = s._usdn;
        uint256 minUsdnSharesSupply = usdn.convertToShares(Constants.MIN_USDN_SUPPLY);
        // mint the minimum amount and send it to the dead address so it can never be removed from the total supply
        usdn.mintShares(Constants.DEAD_ADDRESS, minUsdnSharesSupply);
        // mint the user's share
        uint256 mintSharesToUser = usdnSharesToMint - minUsdnSharesSupply;
        uint256 mintedTokens = usdn.mintShares(msg.sender, mintSharesToUser);

        emit IUsdnProtocolEvents.ValidatedDeposit(
            Constants.DEAD_ADDRESS, Constants.DEAD_ADDRESS, 0, Constants.MIN_USDN_SUPPLY, block.timestamp
        );
        emit IUsdnProtocolEvents.ValidatedDeposit(msg.sender, msg.sender, amount, mintedTokens, block.timestamp);
    }

    /**
     * @notice Creates the initial long position.
     * @dev To be called from `initialize`.
     * @param amount The initial position amount.
     * @param price The current asset price.
     * @param tick The tick corresponding where the position should be stored.
     * @param totalExpo The total expo of the position.
     */
    function _createInitialPosition(uint128 amount, uint128 price, int24 tick, uint128 totalExpo) internal {
        Types.Storage storage s = Utils._getMainStorage();

        // transfer the assets for the long
        address(s._asset).safeTransferFrom(msg.sender, address(this), amount);

        Types.PositionId memory posId;
        posId.tick = tick;
        Types.Position memory long = Types.Position({
            validated: true,
            user: msg.sender,
            amount: amount,
            totalExpo: totalExpo,
            timestamp: uint40(block.timestamp)
        });
        // save the position and update the state
        (posId.tickVersion, posId.index,) = _saveNewPosition(posId.tick, long, s._liquidationPenalty);
        s._balanceLong += long.amount;
        emit IUsdnProtocolEvents.InitiatedOpenPosition(
            msg.sender, msg.sender, long.timestamp, totalExpo, long.amount, price, posId
        );
        emit IUsdnProtocolEvents.ValidatedOpenPosition(msg.sender, msg.sender, totalExpo, price, posId);
    }

    /**
     * @notice Gets the possible pending action for a validator.
     * @dev Checks for the presence of a pending action for a validator, compares `action_.action` to
     * `Types.ProtocolAction.None`. There is a pending action only if the action is different from
     * `Types.ProtocolAction.None`.
     * @param validator The address of the pending action which is supposed to validate the position and receive the
     * security deposit.
     * @return action_ The pending action struct if any, otherwise a zero-initialized struct.
     * @return rawIndex_ The raw index of the pending action in the queue.
     */
    function _getPendingAction(address validator)
        internal
        view
        returns (Types.PendingAction memory action_, uint128 rawIndex_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 pendingActionIndex = s._pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            return (action_, rawIndex_);
        }

        rawIndex_ = uint128(pendingActionIndex - 1);
        action_ = s._pendingActionsQueue.atRaw(rawIndex_);
    }

    /**
     * @notice Checks if the initialize parameters lead to a balanced protocol.
     * @dev Reverts if the imbalance is exceeded for the deposit or open long actions.
     * @param positionTotalExpo The total expo of the deployer's long position.
     * @param longAmount The amount (collateral) of the deployer's long position.
     * @param depositAmount The amount of assets for the deployer's deposit.
     */
    function _checkInitImbalance(uint128 positionTotalExpo, uint128 longAmount, uint128 depositAmount) internal view {
        Types.Storage storage s = Utils._getMainStorage();

        int256 longTradingExpo = Utils._toInt256(positionTotalExpo - longAmount);
        int256 depositLimit = s._depositExpoImbalanceLimitBps;
        // users should be able to open positions after initialization
        // with at least 2 times the minimum amount required for a position without exceeding imbalance limits
        int256 minAmount = int256(s._minLongPosition * 2);

        if (depositLimit != 0) {
            int256 imbalanceBps =
                (Utils._toInt256(depositAmount) - longTradingExpo) * int256(Constants.BPS_DIVISOR) / longTradingExpo;
            if (imbalanceBps > depositLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }

            // make sure that the minAmount can be added as vault balance without imbalancing the protocol
            imbalanceBps = (Utils._toInt256(depositAmount) + minAmount - longTradingExpo)
                * int256(Constants.BPS_DIVISOR) / longTradingExpo;
            if (imbalanceBps > depositLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolMinInitAmount();
            }
        }

        int256 openLimit = s._openExpoImbalanceLimitBps;
        if (openLimit != 0) {
            int256 imbalanceBps = (longTradingExpo - Utils._toInt256(depositAmount)) * int256(Constants.BPS_DIVISOR)
                / Utils._toInt256(depositAmount);
            if (imbalanceBps > openLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }

            // make sure that the minAmount can be added as trading expo without imbalancing the protocol
            imbalanceBps = (longTradingExpo + minAmount - Utils._toInt256(depositAmount))
                * int256(Constants.BPS_DIVISOR) / Utils._toInt256(depositAmount);
            if (imbalanceBps > openLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolMinInitAmount();
            }
        }
    }

    /**
     * @notice Computes the funding rate per day and the old long exposure.
     * @param ema The EMA of the funding rate per day.
     * @return fundingPerDay_ The funding rate per day with `FUNDING_RATE_DECIMALS` decimals.
     * @return oldLongExpo_ The old long trading expo.
     */
    function _fundingPerDay(int256 ema) internal view returns (int256 fundingPerDay_, int256 oldLongExpo_) {
        Types.Storage storage s = Utils._getMainStorage();

        // imbalanceIndex = (longExpo - vaultExpo) / max(longExpo, vaultExpo)
        // fundingPerDay = (sign(imbalanceIndex) * imbalanceIndex^2 * fundingSF) + _EMA
        // fundingPerDay = (sign(ImbalanceIndex) * (longExpo - vaultExpo)^2 * fundingSF / denominator) + _EMA
        // with denominator = vaultExpo^2 if vaultExpo > longExpo, or longExpo^2 if longExpo > vaultExpo

        oldLongExpo_ = s._totalExpo.toInt256().safeSub(s._balanceLong.toInt256());
        int256 oldVaultExpo = s._balanceVault.toInt256();
        int256 numerator = oldLongExpo_ - oldVaultExpo;
        // optimization: if the numerator is zero, then we simply return the EMA
        if (numerator == 0) {
            return (ema, oldLongExpo_);
        }

        if (oldLongExpo_ <= 0) {
            // if oldLongExpo is negative, then we cap the imbalance index to -1
            // this should never happen, but for safety we handle it anyway
            return (
                -int256(s._fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)) + ema,
                oldLongExpo_
            );
        } else if (oldVaultExpo == 0) {
            // if oldVaultExpo is zero (can't be negative), then we cap the imbalance index to 1
            return (
                int256(s._fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS)) + ema,
                oldLongExpo_
            );
        }

        // starting here, oldLongExpo and oldVaultExpo are always strictly positive
        uint256 numeratorSquared = uint256(numerator * numerator);

        uint256 denominator;
        if (oldVaultExpo > oldLongExpo_) {
            denominator = uint256(oldVaultExpo * oldVaultExpo);
            fundingPerDay_ = -int256(
                FixedPointMathLib.fullMulDiv(
                    numeratorSquared,
                    s._fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        } else {
            denominator = uint256(oldLongExpo_ * oldLongExpo_);
            fundingPerDay_ = int256(
                FixedPointMathLib.fullMulDiv(
                    numeratorSquared,
                    s._fundingSF * 10 ** (Constants.FUNDING_RATE_DECIMALS - Constants.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        }
    }

    /**
     * @notice Computes the funding value, funding rate value and the old long exposure.
     * @dev Reverts if `timestamp` < `s._lastUpdateTimestamp`.
     * @param timestamp The current timestamp.
     * @param ema The EMA of the funding rate per day.
     * @return funding_ The funding (proportion of long trading expo that needs to be transferred from one side to the
     * other) with `FUNDING_RATE_DECIMALS` decimals. If positive, long side pays to vault side, otherwise it's the
     * opposite.
     * @return fundingPerDay_ The funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals.
     * @return oldLongExpo_ The old long trading expo.
     */
    function _funding(uint128 timestamp, int256 ema)
        internal
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        (fundingPerDay_, oldLongExpo_) = _fundingPerDay(ema);

        uint128 lastUpdateTimestamp = s._lastUpdateTimestamp;
        if (timestamp < lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }
        // subtraction can't underflow, checked above
        // conversion from uint128 to int256 is always safe
        int256 elapsedSeconds;
        unchecked {
            elapsedSeconds = Utils._toInt256(timestamp - lastUpdateTimestamp);
        }
        if (elapsedSeconds == 0) {
            return (0, fundingPerDay_, oldLongExpo_);
        }

        funding_ = fundingPerDay_.safeMul(elapsedSeconds).safeDiv(1 days);
    }

    /**
     * @notice Calculates the new Exponential Moving Average.
     * @param fundingPerDay The funding per day.
     * @param secondsElapsed The number of seconds elapsed to be taken into account.
     * @param emaPeriod The current EMA period.
     * @param previousEMA The previous EMA value.
     * @return newEMA_ The new EMA value.
     */
    function _calcEMA(int256 fundingPerDay, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        internal
        pure
        returns (int256 newEMA_)
    {
        if (secondsElapsed >= emaPeriod) {
            return fundingPerDay;
        }

        return (
            fundingPerDay * Utils._toInt256(secondsElapsed) + previousEMA * Utils._toInt256(emaPeriod - secondsElapsed)
        ) / Utils._toInt256(emaPeriod);
    }

    /**
     * @notice Calculates the maximum value of the long balance for the provided total expo.
     * @param totalExpo The total expo of the long side of the protocol.
     * @return maxLongBalance_ The maximum value the long balance can reach.
     */
    function _calcMaxLongBalance(uint256 totalExpo) internal pure returns (uint256 maxLongBalance_) {
        maxLongBalance_ = FixedPointMathLib.fullMulDiv(
            totalExpo, (Constants.BPS_DIVISOR - Constants.MIN_LONG_TRADING_EXPO_BPS), Constants.BPS_DIVISOR
        );
    }
}
