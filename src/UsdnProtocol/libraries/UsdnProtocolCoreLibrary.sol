// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolCore } from "../../interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { DoubleEndedQueue } from "../../libraries/DoubleEndedQueue.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { Storage } from "../UsdnProtocolStorage.sol";
import { IUsdnProtocolEvents } from "./../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "./../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from "./UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolActionsVaultLibrary as actionsVaultLib } from "./UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolLongLibrary as longLib } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolConstantsLibrary as constantsLib } from "./UsdnProtocolConstantsLibrary.sol";
import {
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    PositionId,
    Position,
    TickData
} from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

library UsdnProtocolCoreLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using SignedMath for int256;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using LibBitmap for LibBitmap.Bitmap;
    using HugeUint for HugeUint.Uint512;

    // TO DO : not here
    // / @inheritdoc IUsdnProtocolCore
    uint256 internal constant MAX_ACTIONABLE_PENDING_ACTIONS = 20;

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolCore}
    function initialize(
        Storage storage s,
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) public {
        if (depositAmount < constantsLib.MIN_INIT_DEPOSIT) {
            revert IUsdnProtocolErrors.UsdnProtocolMinInitAmount(constantsLib.MIN_INIT_DEPOSIT);
        }
        if (longAmount < constantsLib.MIN_INIT_DEPOSIT) {
            revert IUsdnProtocolErrors.UsdnProtocolMinInitAmount(constantsLib.MIN_INIT_DEPOSIT);
        }
        // since all USDN must be minted by the protocol, we check that the total supply is 0
        IUsdn usdn = s._usdn;
        if (usdn.totalSupply() != 0) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdn(address(usdn));
        }

        PriceInfo memory currentPrice =
            actionsVaultLib._getOraclePrice(s, ProtocolAction.Initialize, block.timestamp, "", currentPriceData);

        s._lastUpdateTimestamp = uint128(block.timestamp);
        s._lastPrice = currentPrice.price.toUint128();

        int24 tick = longLib.getEffectiveTickForPrice(s, desiredLiqPrice); // without penalty
        uint128 liquidationPriceWithoutPenalty = longLib.getEffectivePriceForTick(s, tick);
        uint128 positionTotalExpo =
            longLib._calcPositionTotalExpo(longAmount, currentPrice.price.toUint128(), liquidationPriceWithoutPenalty);

        vaultLib._checkInitImbalance(s, positionTotalExpo, longAmount, depositAmount);

        vaultLib._createInitialDeposit(s, depositAmount, currentPrice.price.toUint128());

        vaultLib._createInitialPosition(s, longAmount, currentPrice.price.toUint128(), tick, positionTotalExpo);

        actionsVaultLib._refundEther(address(this).balance, payable(msg.sender));
    }

    /* -------------------------- public view functions ------------------------- */

    /// @notice See {IUsdnProtocolCore}
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        pure
        returns (int256)
    {
        if (secondsElapsed >= emaPeriod) {
            return lastFunding;
        }

        return (lastFunding + previousEMA * _toInt256(emaPeriod - secondsElapsed)) / _toInt256(emaPeriod);
    }

    /* --------------------------  public functions --------------------------- */

    /// @notice See {IUsdnProtocolCore}
    function funding(Storage storage s, uint128 timestamp) public view returns (int256 fund_, int256 oldLongExpo_) {
        (fund_, oldLongExpo_) = _funding(s, timestamp, s._EMA);
    }

    /// @notice See {IUsdnProtocolCore}
    function vaultTradingExpoWithFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 expo_)
    {
        expo_ = vaultLib.vaultAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    /// @notice See {IUsdnProtocolCore}
    function getActionablePendingActions(Storage storage s, address currentUser)
        public
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (actions_, rawIndices_);
        }
        actions_ = new PendingAction[](MAX_ACTIONABLE_PENDING_ACTIONS);
        rawIndices_ = new uint128[](MAX_ACTIONABLE_PENDING_ACTIONS);
        uint256 maxIter = MAX_ACTIONABLE_PENDING_ACTIONS;
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        uint256 arrayLen = 0;
        do {
            // since `i` cannot be greater or equal to `queueLength`, there is no risk of reverting
            (PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.at(i);
            // if the msg.sender is equal to the validator of the pending action, then the pending action is not
            // actionable by this user (it will get validated automatically by their action)
            // and so we need to return the next item in the queue so that they can validate a third-party pending
            // action (if any)
            if (candidate.timestamp == 0 || candidate.validator == currentUser) {
                rawIndices_[i] = rawIndex;
                // try the next one
                unchecked {
                    i++;
                }
            } else if (candidate.timestamp + s._validationDeadline < block.timestamp) {
                // we found an actionable pending action
                actions_[i] = candidate;
                rawIndices_[i] = rawIndex;

                // continue looking
                unchecked {
                    i++;
                    arrayLen = i;
                }
            } else {
                // the pending action is not actionable (it is too recent),
                // following actions can't be actionable either so we return
                break;
            }
        } while (i < maxIter);
        assembly {
            // shrink the size of the arrays
            mstore(actions_, arrayLen)
            mstore(rawIndices_, arrayLen)
        }
    }

    /// @notice See {IUsdnProtocolCore}
    function getUserPendingAction(Storage storage s, address user) public view returns (PendingAction memory action_) {
        (action_,) = _getPendingAction(s, user);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Calculate the funding rate and the old long exposure
     * @param s The storage of the protocol
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fund_ The funding rate
     * @return oldLongExpo_ The old long exposure
     */
    function _funding(Storage storage s, uint128 timestamp, int256 ema)
        public
        view
        returns (int256 fund_, int256 oldLongExpo_)
    {
        oldLongExpo_ = s._totalExpo.toInt256().safeSub(s._balanceLong.toInt256());

        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        } else if (timestamp == s._lastUpdateTimestamp) {
            return (0, oldLongExpo_);
        }

        int256 oldVaultExpo = s._balanceVault.toInt256();

        // ImbalanceIndex = (longExpo - vaultExpo) / max(longExpo, vaultExpo)
        // fund = (sign(ImbalanceIndex) * ImbalanceIndex^2 * fundingSF) +s.
        // fund = (sign(ImbalanceIndex) * (longExpo - vaultExpo)^2 * fundingSF / denominator) +s.
        // with denominator = vaultExpo^2 if vaultExpo > longExpo, or longExpo^2 if longExpo > vaultExpo

        int256 numerator = oldLongExpo_ - oldVaultExpo;
        // optimization: if the numerator is zero, then return the EMA
        if (numerator == 0) {
            return (ema, oldLongExpo_);
        }

        if (oldLongExpo_ <= 0) {
            // if oldLongExpo is negative, then we cap the imbalance index to -1
            // oldVaultExpo is always positive
            return (
                -int256(s._fundingSF * 10 ** (constantsLib.FUNDING_RATE_DECIMALS - constantsLib.FUNDING_SF_DECIMALS))
                    + ema,
                oldLongExpo_
            );
        } else if (oldVaultExpo == 0) {
            // if oldVaultExpo is zero (can't be negative), then we cap the imbalance index to 1
            // oldLongExpo must be positive in this case
            return (
                int256(s._fundingSF * 10 ** (constantsLib.FUNDING_RATE_DECIMALS - constantsLib.FUNDING_SF_DECIMALS))
                    + ema,
                oldLongExpo_
            );
        }

        // starting here, oldLongExpo and oldVaultExpo are always strictly positive

        uint256 elapsedSeconds = timestamp - s._lastUpdateTimestamp;
        uint256 numerator_squared = uint256(numerator * numerator);

        uint256 denominator;
        if (oldVaultExpo > oldLongExpo_) {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldVaultExpo * oldVaultExpo) * 1 days;
            fund_ = -int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    s._fundingSF * 10 ** (constantsLib.FUNDING_RATE_DECIMALS - constantsLib.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        } else {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldLongExpo_ * oldLongExpo_) * 1 days;
            fund_ = int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    s._fundingSF * 10 ** (constantsLib.FUNDING_RATE_DECIMALS - constantsLib.FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        }
    }

    /**
     * @notice Get the predicted value of the funding (in asset units) since the last state update for the given
     * timestamp
     * @dev If the provided timestamp is older than the last state update, the result will be zero
     * @param s The storage of the protocol
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fundingAsset_ The number of asset tokens of funding (with asset decimals)
     * @return fund_ The magnitude of the funding (with `FUNDING_RATE_DECIMALS` decimals)
     */
    function _fundingAsset(Storage storage s, uint128 timestamp, int256 ema)
        public
        view
        returns (int256 fundingAsset_, int256 fund_)
    {
        int256 oldLongExpo;
        (fund_, oldLongExpo) = _funding(s, timestamp, ema);
        fundingAsset_ = fund_.safeMul(oldLongExpo) / int256(10) ** constantsLib.FUNDING_RATE_DECIMALS;
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`
     * @param s The storage of the protocol
     * @param currentPrice The current price
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(Storage storage s, uint128 currentPrice) public view returns (int256 available_) {
        available_ = _longAssetAvailable(s._totalExpo, s._balanceLong, currentPrice, s._lastPrice);
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        public
        pure
        returns (int256 available_)
    {
        // if balanceLong == totalExpo or the long trading expo is negative (theoretically impossible), the PnL is
        // zero
        // we can't calculate a proper PnL value if the long trading expo is negative because it would invert the
        // sign of the amount
        if (balanceLong >= totalExpo) {
            return balanceLong.toInt256();
        }
        int256 priceDiff = _toInt256(newPrice) - _toInt256(oldPrice);
        uint256 tradingExpo;
        // `balanceLong` is strictly inferior to `totalExpo`
        unchecked {
            tradingExpo = totalExpo - balanceLong;
        }
        int256 pnl = tradingExpo.toInt256().safeMul(priceDiff).safeDiv(_toInt256(newPrice));

        available_ = balanceLong.toInt256().safeAdd(pnl);
    }

    /**
     * @notice Update the Exponential Moving Average (EMA) of the funding
     * @dev This function is called every time the protocol state is updated
     * @dev All required checks are done in the caller function (_applyPnlAndFunding)
     * @dev If the number of seconds elapsed is greater than or equal to the EMA period, the EMA is updated to the last
     * funding value
     * @param s The storage of the protocol
     * @param secondsElapsed The number of seconds elapsed since the last protocol action
     * @return The new EMA value
     */
    function _updateEMA(Storage storage s, uint128 secondsElapsed) public returns (int256) {
        return s._EMA = calcEMA(s._lastFunding, secondsElapsed, s._EMAPeriod, s._EMA);
    }

    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function _toInt256(uint128 x) public pure returns (int256) {
        return int256(uint256(x));
    }

    /**
     * @notice Calculate the protocol fee and apply it to the funding asset amount
     * @dev The funding factor is only adjusted by the fee rate when the funding is negative (vault pays to the long
     * side)
     * @param s The storage of the protocol
     * @param fund The funding factor
     * @param fundAsset The funding asset amount to be used for the fee calculation
     * @return fee_ The absolute value of the calculated fee
     * @return fundWithFee_ The updated funding factor after applying the fee
     * @return fundAssetWithFee_ The updated funding asset amount after applying the fee
     */
    function _calculateFee(Storage storage s, int256 fund, int256 fundAsset)
        public
        returns (int256 fee_, int256 fundWithFee_, int256 fundAssetWithFee_)
    {
        int256 protocolFeeBps = _toInt256(s._protocolFeeBps);
        fundWithFee_ = fund;
        fee_ = fundAsset * protocolFeeBps / int256(constantsLib.BPS_DIVISOR);
        // fundAsset and fee_ have the same sign, we can safely subtract them to reduce the absolute amount of asset
        fundAssetWithFee_ = fundAsset - fee_;

        if (fee_ < 0) {
            // when funding is negative, the part that is taken as fees does not contribute to the liquidation
            // multiplier adjustment, and so we should deduce it from the funding factor
            fundWithFee_ -= fund * protocolFeeBps / int256(constantsLib.BPS_DIVISOR);
            // we want to return the absolute value of the fee
            fee_ = -fee_;
        }

        s._pendingProtocolFee += uint256(fee_);
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `WithdrawalPendingAction`
     * @param sharesLSB The lower 24 bits of the USDN shares
     * @param sharesMSB The higher bits of the USDN shares
     * @return usdnShares_ The amount of USDN shares
     */
    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        public
        pure
        returns (uint256 usdnShares_)
    {
        usdnShares_ = sharesLSB | uint256(sharesMSB) << 24;
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the tick spacing in storage
     * @param s The storage of the protocol
     * @param tick The tick to convert, a multiple of the tick spacing
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(Storage storage s, int24 tick) public view returns (uint256 index_) {
        index_ = _calcBitmapIndexFromTick(tick, s._tickSpacing);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the provided tick spacing
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @param tickSpacing The tick spacing to use
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) public pure returns (uint256 index_) {
        index_ = uint256( // cast is safe as the min tick is always above TickMath.MIN_TICK
            (int256(tick) - TickMath.MIN_TICK) // shift into positive
                / tickSpacing
        );
    }

    /**
     * @notice Calculate the profits and losses of the long side, calculate the funding and apply protocol fees,
     * calculate the new liquidation multiplier and the temporary new balances for each side
     * @dev This function updates the state of `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding`, but does not
     * update the balances. This is left to the caller
     * @param s The storage of the protocol
     * @param currentPrice The current price
     * @param timestamp The timestamp of the current price
     * @return isPriceRecent_ Whether the price was updated or was already the most recent price
     * @return tempLongBalance_ The new balance of the long side, could be negative (temporarily)
     * @return tempVaultBalance_ The new balance of the vault side, could be negative (temporarily)
     */
    function _applyPnlAndFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        returns (bool isPriceRecent_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        int256 fundAsset;
        int256 fund;
        {
            // cache variable for optimization
            uint128 lastUpdateTimestamp = s._lastUpdateTimestamp;
            // if the price is not fresh, do nothing
            if (timestamp <= lastUpdateTimestamp) {
                return (timestamp == lastUpdateTimestamp, s._balanceLong.toInt256(), s._balanceVault.toInt256());
            }

            // update the funding EMA
            int256 ema = _updateEMA(s, timestamp - lastUpdateTimestamp);

            // calculate the funding
            (fundAsset, fund) = _fundingAsset(s, timestamp, ema);
        }

        // take protocol fee on the funding value
        (int256 fee, int256 fundWithFee, int256 fundAssetWithFee) = _calculateFee(s, fund, fundAsset);

        // we subtract the fee from the total balance
        int256 totalBalance = s._balanceLong.toInt256();
        totalBalance = totalBalance.safeAdd(s._balanceVault.toInt256()).safeSub(fee);
        // calculate new balances (for now, any bad debt has not been repaid, balances could become negative)

        if (fund > 0) {
            // in case of positive funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the vault balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(s, currentPrice).safeSub(fundAsset);
        } else {
            // in case of negative funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the long balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(s, currentPrice).safeSub(fundAssetWithFee);
        }
        tempVaultBalance_ = totalBalance.safeSub(tempLongBalance_);

        // update state variables
        s._lastPrice = currentPrice;
        s._lastUpdateTimestamp = timestamp;
        s._lastFunding = fundWithFee;

        isPriceRecent_ = true;
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
        public
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `WithdrawalPendingAction` to a `PendingAction`
     * @param action A withdrawal pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        public
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `LongPendingAction` to a `PendingAction`
     * @param action A long pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertLongPendingAction(LongPendingAction memory action)
        public
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
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
        uint256 maxIter = MAX_ACTIONABLE_PENDING_ACTIONS;
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
     * @notice Remove the pending action from the queue if its tick version doesn't match the current tick version
     * @dev This is only applicable to `ValidateOpenPosition` pending actions
     * @param s The storage of the protocol
     * @param user The user's address
     * @return securityDepositValue_ The security deposit value of the removed stale pending action
     */
    function _removeStalePendingAction(Storage storage s, address user)
        public
        returns (uint256 securityDepositValue_)
    {
        if (s._pendingActions[user] == 0) {
            return 0;
        }
        (PendingAction memory action, uint128 rawIndex) = _getPendingAction(s, user);
        // the position is only at risk of being liquidated while pending if it is an open position action
        if (action.action == ProtocolAction.ValidateOpenPosition) {
            LongPendingAction memory openAction = _toLongPendingAction(action);
            uint256 version = s._tickVersion[openAction.tick];
            if (version != openAction.tickVersion) {
                securityDepositValue_ = openAction.securityDepositValue;
                // the position was liquidated while pending
                // remove the stale pending action
                s._pendingActionsQueue.clearAt(rawIndex);
                delete s._pendingActions[user];
                emit IUsdnProtocolEvents.StalePendingActionRemoved(
                    user,
                    PositionId({ tick: openAction.tick, tickVersion: openAction.tickVersion, index: openAction.index })
                );
            }
        }
    }

    /**
     * @notice Add a pending action to the queue
     * @dev This reverts if there is already a pending action for this user
     * @param s The storage of the protocol
     * @param user The user's address
     * @param action The pending action struct
     * @return amountToRefund_ The security deposit value of the stale pending action
     */
    function _addPendingAction(Storage storage s, address user, PendingAction memory action)
        public
        returns (uint256 amountToRefund_)
    {
        amountToRefund_ = _removeStalePendingAction(s, user); // check if there is a pending action that was
            // liquidated and remove it
        if (s._pendingActions[user] > 0) {
            revert IUsdnProtocolErrors.UsdnProtocolPendingAction();
        }
        // add the action to the queue
        uint128 rawIndex = s._pendingActionsQueue.pushBack(action);
        // store the index shifted by one, so that zero means no pending action
        s._pendingActions[user] = uint256(rawIndex) + 1;
    }

    /**
     * @notice Get the pending action for a user
     * @dev To check for the presence of a pending action, compare `action_.action` to `ProtocolAction.None`. There is
     * a pending action only if the action is different from `ProtocolAction.None`
     * @param s The storage of the protocol
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
        if (pendingActionIndex == 0) {
            // no pending action
            return (action_, rawIndex_);
        }

        rawIndex_ = uint128(pendingActionIndex - 1);
        action_ = s._pendingActionsQueue.atRaw(rawIndex_);
    }

    /**
     * @notice Get the pending action for a user
     * @dev This function reverts if there is no pending action for the user
     * @param s The storage of the protocol
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
     * @notice Clear the pending action for a user
     * @param s The storage of the protocol
     * @param user The user's address
     * @param rawIndex The rawIndex of the pending action in the queue
     */
    function _clearPendingAction(Storage storage s, address user, uint128 rawIndex) public {
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Remove a stuck pending action and perform the minimal amount of cleanup necessary
     * @dev This function should only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to somethingpublic reverting unexpectedly
     * The caller must wait at least 1 hour after the validation deadline to call this function. This is to give the
     * chance to normal users to validate the action if possible
     * @param s The storage of the protocol
     * @param rawIndex The raw index of the pending action in the queue
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn)
     * @param cleanup If `true`, will attempt to perform more cleanup at the risk of reverting. Always try `true` first
     */
    function _removeBlockedPendingAction(Storage storage s, uint128 rawIndex, address payable to, bool cleanup)
        public
    {
        PendingAction memory pending = s._pendingActionsQueue.atRaw(rawIndex);
        if (block.timestamp < pending.timestamp + s._validationDeadline + 1 hours) {
            revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
        }
        delete s._pendingActions[pending.validator];
        s._pendingActionsQueue.clearAt(rawIndex);
        if (pending.action == ProtocolAction.ValidateDeposit && cleanup) {
            // for pending deposits, we send back the locked assets
            DepositPendingAction memory deposit = _toDepositPendingAction(pending);
            s._pendingBalanceVault -= _toInt256(deposit.amount);
            address(s._asset).safeTransfer(to, deposit.amount);
        } else if (pending.action == ProtocolAction.ValidateWithdrawal && cleanup) {
            // for pending withdrawals, we send the locked USDN
            WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);
            uint256 shares = _mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);
            uint256 pendingAmount =
                FixedPointMathLib.fullMulDiv(shares, withdrawal.balanceVault, withdrawal.usdnTotalShares);
            s._pendingBalanceVault += pendingAmount.toInt256();
            s._usdn.transferShares(to, shares);
        } else if (pending.action == ProtocolAction.ValidateOpenPosition) {
            // for pending opens, we need to remove the position
            LongPendingAction memory open = _toLongPendingAction(pending);
            (bytes32 tickHash, uint256 tickVersion) = vaultLib._tickHash(s, open.tick);
            if (tickVersion == open.tickVersion) {
                // we only need to modify storage if the pos was not liquidated already

                // safe cleanup operations
                Position[] storage tickArray = s._longPositions[tickHash];
                Position memory pos = tickArray[open.index];
                delete s._longPositions[tickHash][open.index];

                // more cleanup operations
                if (cleanup) {
                    TickData storage tickData = s._tickData[tickHash];
                    --s._totalLongPositions;
                    tickData.totalPos -= 1;
                    if (tickData.totalPos == 0) {
                        // we removed the last position in the tick
                        s._tickBitmap.unset(_calcBitmapIndexFromTick(s, open.tick));
                    }
                    uint256 unadjustedTickPrice =
                        TickMath.getPriceAtTick(open.tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
                    s._totalExpo -= pos.totalExpo;
                    tickData.totalExpo -= pos.totalExpo;
                    s._liqMultiplierAccumulator =
                        s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * pos.totalExpo));
                }
            }
        } else if (pending.action == ProtocolAction.ValidateClosePosition && cleanup) {
            // for pending closes, the position is already out of the protocol
            LongPendingAction memory close = _toLongPendingAction(pending);
            // credit the full amount to the vault to preserve the total balance invariant (like a liquidation)
            s._balanceVault += close.closeBoundedPositionValue;
        }

        // we retrieve the security deposit
        if (cleanup) {
            (bool success,) = to.call{ value: pending.securityDepositValue }("");
            if (!success) {
                revert IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed();
            }
        }
    }
}
