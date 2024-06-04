// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { IUsdnProtocolCore } from "src/interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import {
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    PositionId,
    Position,
    TickData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";

abstract contract UsdnProtocolCore is IUsdnProtocolCore, UsdnProtocolStorage {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using LibBitmap for LibBitmap.Bitmap;
    using HugeUint for HugeUint.Uint512;

    /// @inheritdoc IUsdnProtocolCore
    address public constant DEAD_ADDRESS = address(0xdead);

    /// @inheritdoc IUsdnProtocolCore
    uint256 public constant MAX_ACTIONABLE_PENDING_ACTIONS = 20;

    /* -------------------------- Public view functions ------------------------- */

    /// @inheritdoc IUsdnProtocolCore
    function funding(uint128 timestamp) public view returns (int256 fund_, int256 oldLongExpo_) {
        (fund_, oldLongExpo_) = _funding(timestamp, _EMA);
    }

    /// @inheritdoc IUsdnProtocolCore
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < _lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
        }

        int256 ema = calcEMA(_lastFunding, timestamp - _lastUpdateTimestamp, _EMAPeriod, _EMA);
        (int256 fundAsset,) = _fundingAsset(timestamp, ema);

        if (fundAsset > 0) {
            available_ = _longAssetAvailable(currentPrice).safeSub(fundAsset);
        } else {
            int256 fee = fundAsset * _toInt256(_protocolFeeBps) / int256(BPS_DIVISOR);
            // fees have the same sign as fundAsset (negative here), so we need to sub them
            available_ = _longAssetAvailable(currentPrice).safeSub(fundAsset - fee);
        }
    }

    /// @inheritdoc IUsdnProtocolCore
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < _lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
        }

        int256 ema = calcEMA(_lastFunding, timestamp - _lastUpdateTimestamp, _EMAPeriod, _EMA);
        (int256 fundAsset,) = _fundingAsset(timestamp, ema);

        if (fundAsset < 0) {
            available_ = _vaultAssetAvailable(currentPrice).safeAdd(fundAsset);
        } else {
            int256 fee = fundAsset * _toInt256(_protocolFeeBps) / int256(BPS_DIVISOR);
            available_ = _vaultAssetAvailable(currentPrice).safeAdd(fundAsset - fee);
        }
    }

    /// @inheritdoc IUsdnProtocolCore
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public view returns (int256 expo_) {
        expo_ = _totalExpo.toInt256().safeSub(longAssetAvailableWithFunding(currentPrice, timestamp));
    }

    /// @inheritdoc IUsdnProtocolCore
    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 expo_)
    {
        expo_ = vaultAssetAvailableWithFunding(currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolCore
    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        uint256 queueLength = _pendingActionsQueue.length();
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
            (PendingAction memory candidate, uint128 rawIndex) = _pendingActionsQueue.at(i);
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
            } else if (candidate.timestamp + _validationDeadline < block.timestamp) {
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

    /// @inheritdoc IUsdnProtocolCore
    function getUserPendingAction(address user) external view returns (PendingAction memory action_) {
        (action_,) = _getPendingAction(user);
    }

    /// @inheritdoc IUsdnProtocolCore
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

    /* --------------------------  Internal functions --------------------------- */

    /**
     * @notice Calculate the funding rate and the old long exposure
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fund_ The funding rate
     * @return oldLongExpo_ The old long exposure
     */
    function _funding(uint128 timestamp, int256 ema) internal view returns (int256 fund_, int256 oldLongExpo_) {
        oldLongExpo_ = _totalExpo.toInt256().safeSub(_balanceLong.toInt256());

        if (timestamp < _lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
            // slither-disable-next-line incorrect-equality
        } else if (timestamp == _lastUpdateTimestamp) {
            return (0, oldLongExpo_);
        }

        int256 oldVaultExpo = _balanceVault.toInt256();

        // ImbalanceIndex = (longExpo - vaultExpo) / max(longExpo, vaultExpo)
        // fund = (sign(ImbalanceIndex) * ImbalanceIndex^2 * fundingSF) + _EMA
        // fund = (sign(ImbalanceIndex) * (longExpo - vaultExpo)^2 * fundingSF / denominator) + _EMA
        // with denominator = vaultExpo^2 if vaultExpo > longExpo, or longExpo^2 if longExpo > vaultExpo

        int256 numerator = oldLongExpo_ - oldVaultExpo;
        // optimization: if the numerator is zero, then return the EMA
        // slither-disable-next-line incorrect-equality
        if (numerator == 0) {
            return (ema, oldLongExpo_);
        }

        if (oldLongExpo_ <= 0) {
            // if oldLongExpo is negative, then we cap the imbalance index to -1
            // oldVaultExpo is always positive
            return (-int256(_fundingSF * 10 ** (FUNDING_RATE_DECIMALS - FUNDING_SF_DECIMALS)) + ema, oldLongExpo_);
        } else if (oldVaultExpo == 0) {
            // if oldVaultExpo is zero (can't be negative), then we cap the imbalance index to 1
            // oldLongExpo must be positive in this case
            return (int256(_fundingSF * 10 ** (FUNDING_RATE_DECIMALS - FUNDING_SF_DECIMALS)) + ema, oldLongExpo_);
        }

        // starting here, oldLongExpo and oldVaultExpo are always strictly positive

        uint256 elapsedSeconds = timestamp - _lastUpdateTimestamp;
        uint256 numerator_squared = uint256(numerator * numerator);

        uint256 denominator;
        if (oldVaultExpo > oldLongExpo_) {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldVaultExpo * oldVaultExpo) * 1 days;
            fund_ = -int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    _fundingSF * 10 ** (FUNDING_RATE_DECIMALS - FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        } else {
            // we have to multiply by 1 day to get the correct units
            denominator = uint256(oldLongExpo_ * oldLongExpo_) * 1 days;
            fund_ = int256(
                FixedPointMathLib.fullMulDiv(
                    numerator_squared * elapsedSeconds,
                    _fundingSF * 10 ** (FUNDING_RATE_DECIMALS - FUNDING_SF_DECIMALS),
                    denominator
                )
            ) + ema;
        }
    }

    /**
     * @notice Get the predicted value of the funding (in asset units) since the last state update for the given
     * timestamp
     * @dev If the provided timestamp is older than the last state update, the result will be zero
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fundingAsset_ The number of asset tokens of funding (with asset decimals)
     * @return fund_ The magnitude of the funding (with `FUNDING_RATE_DECIMALS` decimals)
     */
    function _fundingAsset(uint128 timestamp, int256 ema) internal view returns (int256 fundingAsset_, int256 fund_) {
        int256 oldLongExpo;
        (fund_, oldLongExpo) = _funding(timestamp, ema);
        fundingAsset_ = fund_.safeMul(oldLongExpo) / int256(10) ** FUNDING_RATE_DECIMALS;
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`
     * @param currentPrice The current price
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        available_ = _longAssetAvailable(_totalExpo, _balanceLong, currentPrice, _lastPrice);
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
        internal
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
        // `balanceLong` is strictly inferior to totalExpo
        unchecked {
            tradingExpo = totalExpo - balanceLong;
        }
        int256 pnl = tradingExpo.toInt256().safeMul(priceDiff).safeDiv(_toInt256(newPrice));

        available_ = balanceLong.toInt256().safeAdd(pnl);
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param currentPrice Current price
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        available_ = _vaultAssetAvailable(_totalExpo, _balanceVault, _balanceLong, currentPrice, _lastPrice);
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param totalExpo The total expo
     * @param balanceVault The (old) balance of the vault
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balances were updated
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) internal pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = _longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);

        available_ = totalBalance.safeSub(newLongBalance);
    }

    /**
     * @notice Calculate the profits and losses of the long side, calculate the funding and apply protocol fees,
     * calculate the new liquidation multiplier and the temporary new balances for each side
     * @dev This function updates the state of `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding`, but does not
     * update the balances. This is left to the caller
     * @param currentPrice The current price
     * @param timestamp The timestamp of the current price
     * @return isPriceRecent_ Whether the price was updated or was already the most recent price
     * @return tempLongBalance_ The new balance of the long side, could be negative (temporarily)
     * @return tempVaultBalance_ The new balance of the vault side, could be negative (temporarily)
     */
    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        internal
        returns (bool isPriceRecent_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        // cache variable for optimization
        uint128 lastUpdateTimestamp = _lastUpdateTimestamp;
        // if the price is not fresh, do nothing
        if (timestamp <= lastUpdateTimestamp) {
            return (timestamp == lastUpdateTimestamp, _balanceLong.toInt256(), _balanceVault.toInt256());
        }

        // update the funding EMA
        int256 ema = _updateEMA(timestamp - lastUpdateTimestamp);

        // calculate the funding
        (int256 fundAsset, int256 fund) = _fundingAsset(timestamp, ema);

        // take protocol fee on the funding value
        (int256 fee, int256 fundWithFee, int256 fundAssetWithFee) = _calculateFee(fund, fundAsset);

        // we subtract the fee from the total balance
        int256 totalBalance = _balanceLong.toInt256().safeAdd(_balanceVault.toInt256()).safeSub(fee);
        // calculate new balances (for now, any bad debt has not been repaid, balances could become negative)

        if (fund > 0) {
            // in case of positive funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the vault balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(currentPrice).safeSub(fundAsset);
        } else {
            // in case of negative funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the long balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = _longAssetAvailable(currentPrice).safeSub(fundAssetWithFee);
        }
        tempVaultBalance_ = totalBalance.safeSub(tempLongBalance_);

        // update state variables
        _lastPrice = currentPrice;
        _lastUpdateTimestamp = timestamp;
        _lastFunding = fundWithFee;

        isPriceRecent_ = true;
    }

    /**
     * @notice Update the Exponential Moving Average (EMA) of the funding
     * @dev This function is called every time the protocol state is updated
     * @dev All required checks are done in the caller function (_applyPnlAndFunding)
     * @dev If the number of seconds elapsed is greater than or equal to the EMA period, the EMA is updated to the last
     * funding value
     * @param secondsElapsed The number of seconds elapsed since the last protocol action
     * @return The new EMA value
     */
    function _updateEMA(uint128 secondsElapsed) internal returns (int256) {
        return _EMA = calcEMA(_lastFunding, secondsElapsed, _EMAPeriod, _EMA);
    }

    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function _toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    /**
     * @notice Function to calculate the hash and version of a given tick
     * @param tick The tick
     * @return hash_ The hash of the tick
     * @return version_ The version of the tick
     */
    function _tickHash(int24 tick) internal view returns (bytes32 hash_, uint256 version_) {
        version_ = _tickVersion[tick];
        hash_ = tickHash(tick, version_);
    }

    /**
     * @notice Calculate the protocol fee and apply it to the funding asset amount
     * @dev The funding factor is only adjusted by the fee rate when the funding is negative (vault pays to the long
     * side)
     * @param fund The funding factor
     * @param fundAsset The funding asset amount to be used for the fee calculation
     * @return fee_ The absolute value of the calculated fee
     * @return fundWithFee_ The updated funding factor after applying the fee
     * @return fundAssetWithFee_ The updated funding asset amount after applying the fee
     */
    function _calculateFee(int256 fund, int256 fundAsset)
        internal
        returns (int256 fee_, int256 fundWithFee_, int256 fundAssetWithFee_)
    {
        int256 protocolFeeBps = _toInt256(_protocolFeeBps);
        fundWithFee_ = fund;
        fee_ = fundAsset * protocolFeeBps / int256(BPS_DIVISOR);
        // fundAsset and fee_ have the same sign, we can safely subtract them to reduce the absolute amount of asset
        fundAssetWithFee_ = fundAsset - fee_;

        if (fee_ < 0) {
            // when funding is negative, the part that is taken as fees does not contribute to the liquidation
            // multiplier adjustment, and so we should deduce it from the funding factor
            fundWithFee_ -= fund * protocolFeeBps / int256(BPS_DIVISOR);
            // we want to return the absolute value of the fee
            fee_ = -fee_;
        }

        _pendingProtocolFee += uint256(fee_);
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `WithdrawalPendingAction`
     * @param sharesLSB The lower 24 bits of the USDN shares
     * @param sharesMSB The higher bits of the USDN shares
     * @return usdnShares_ The amount of USDN shares
     */
    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        internal
        pure
        returns (uint256 usdnShares_)
    {
        usdnShares_ = sharesLSB | uint256(sharesMSB) << 24;
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the tick spacing in storage
     * @param tick The tick to convert, a multiple of the tick spacing
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick) internal view returns (uint256 index_) {
        index_ = _calcBitmapIndexFromTick(tick, _tickSpacing);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the provided tick spacing
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @param tickSpacing The tick spacing to use
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) internal pure returns (uint256 index_) {
        index_ = uint256( // cast is safe as the min tick is always above TickMath.MIN_TICK
            (int256(tick) - TickMath.MIN_TICK) // shift into positive
                / tickSpacing
        );
    }

    /* -------------------------- Pending actions queue ------------------------- */

    /**
     * @notice Convert a `PendingAction` to a `DepositPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted deposit pending action
     */
    function _toDepositPendingAction(PendingAction memory action)
        internal
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
        internal
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
        internal
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
        internal
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
        internal
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
        internal
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
    function _getActionablePendingAction() internal returns (PendingAction memory action_, uint128 rawIndex_) {
        uint256 queueLength = _pendingActionsQueue.length();
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
            (PendingAction memory candidate, uint128 rawIndex) = _pendingActionsQueue.front();
            // gas optimization
            unchecked {
                i++;
            }
            if (candidate.timestamp == 0) {
                // remove the stale pending action
                // slither-disable-next-line unused-return
                _pendingActionsQueue.popFront();
                // try the next one
                continue;
            } else if (candidate.timestamp + _validationDeadline < block.timestamp) {
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
     * @param user The user's address
     * @return securityDepositValue_ The security deposit value of the removed stale pending action
     */
    function _removeStalePendingAction(address user) internal returns (uint256 securityDepositValue_) {
        // slither-disable-next-line incorrect-equality
        if (_pendingActions[user] == 0) {
            return 0;
        }
        (PendingAction memory action, uint128 rawIndex) = _getPendingAction(user);
        // the position is only at risk of being liquidated while pending if it is an open position action
        // slither-disable-next-line incorrect-equality
        if (action.action == ProtocolAction.ValidateOpenPosition) {
            LongPendingAction memory openAction = _toLongPendingAction(action);
            uint256 version = _tickVersion[openAction.tick];
            if (version != openAction.tickVersion) {
                securityDepositValue_ = openAction.securityDepositValue;
                // the position was liquidated while pending
                // remove the stale pending action
                _pendingActionsQueue.clearAt(rawIndex);
                delete _pendingActions[user];
                emit StalePendingActionRemoved(
                    user,
                    PositionId({ tick: openAction.tick, tickVersion: openAction.tickVersion, index: openAction.index })
                );
            }
        }
    }

    /**
     * @notice Add a pending action to the queue
     * @dev This reverts if there is already a pending action for this user
     * @param user The user's address
     * @param action The pending action struct
     * @return amountToRefund_ The security deposit value of the stale pending action
     */
    function _addPendingAction(address user, PendingAction memory action) internal returns (uint256 amountToRefund_) {
        amountToRefund_ = _removeStalePendingAction(user); // check if there is a pending action that was
            // liquidated and remove it
        if (_pendingActions[user] > 0) {
            revert UsdnProtocolPendingAction();
        }
        // add the action to the queue
        uint128 rawIndex = _pendingActionsQueue.pushBack(action);
        // store the index shifted by one, so that zero means no pending action
        _pendingActions[user] = uint256(rawIndex) + 1;
    }

    /**
     * @notice Get the pending action for a user
     * @dev To check for the presence of a pending action, compare `action_.action` to `ProtocolAction.None`. There is
     * a pending action only if the action is different from `ProtocolAction.None`
     * @param user The user's address
     * @return action_ The pending action struct if any, otherwise a zero-initialized struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingAction(address user) internal view returns (PendingAction memory action_, uint128 rawIndex_) {
        uint256 pendingActionIndex = _pendingActions[user];
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            // no pending action
            return (action_, rawIndex_);
        }

        rawIndex_ = uint128(pendingActionIndex - 1);
        action_ = _pendingActionsQueue.atRaw(rawIndex_);
    }

    /**
     * @notice Get the pending action for a user
     * @dev This function reverts if there is no pending action for the user
     * @param user The user's address
     * @return action_ The pending action struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingActionOrRevert(address user)
        internal
        view
        returns (PendingAction memory action_, uint128 rawIndex_)
    {
        (action_, rawIndex_) = _getPendingAction(user);
        if (action_.action == ProtocolAction.None) {
            revert UsdnProtocolNoPendingAction();
        }
    }

    /**
     * @notice Clear the pending action for a user
     * @param user The user's address
     * @param rawIndex The rawIndex of the pending action in the queue
     */
    function _clearPendingAction(address user, uint128 rawIndex) internal {
        _pendingActionsQueue.clearAt(rawIndex);
        delete _pendingActions[user];
    }

    /**
     * @notice Remove a stuck pending action and perform the minimal amount of cleanup necessary
     * @dev This function should only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly
     * The caller must wait at least 1 hour after the validation deadline to call this function. This is to give the
     * chance to normal users to validate the action if possible
     * @param rawIndex The raw index of the pending action in the queue
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn)
     * @param cleanup If `true`, will attempt to perform more cleanup at the risk of reverting. Always try `true` first
     */
    function _removeBlockedPendingAction(uint128 rawIndex, address payable to, bool cleanup) internal {
        PendingAction memory pending = _pendingActionsQueue.atRaw(rawIndex);
        if (block.timestamp < pending.timestamp + _validationDeadline + 1 hours) {
            revert UsdnProtocolUnauthorized();
        }
        delete _pendingActions[pending.validator];
        _pendingActionsQueue.clearAt(rawIndex);
        if (pending.action == ProtocolAction.ValidateDeposit && cleanup) {
            // for pending deposits, we send back the locked assets
            DepositPendingAction memory deposit = _toDepositPendingAction(pending);
            _pendingBalanceVault -= _toInt256(deposit.amount);
            _asset.safeTransfer(to, deposit.amount);
        } else if (pending.action == ProtocolAction.ValidateWithdrawal && cleanup) {
            // for pending withdrawals, we send the locked USDN
            WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);
            uint256 shares = _mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);
            uint256 pendingAmount =
                FixedPointMathLib.fullMulDiv(shares, withdrawal.balanceVault, withdrawal.usdnTotalShares);
            _pendingBalanceVault += pendingAmount.toInt256();
            _usdn.transferShares(to, shares);
        } else if (pending.action == ProtocolAction.ValidateOpenPosition) {
            // for pending opens, we need to remove the position
            LongPendingAction memory open = _toLongPendingAction(pending);
            (bytes32 tickHash, uint256 tickVersion) = _tickHash(open.tick);
            if (tickVersion == open.tickVersion) {
                // we only need to modify storage if the pos was not liquidated already

                // safe cleanup operations
                Position[] storage tickArray = _longPositions[tickHash];
                Position memory pos = tickArray[open.index];
                delete _longPositions[tickHash][open.index];

                // more cleanup operations
                if (cleanup) {
                    TickData storage tickData = _tickData[tickHash];
                    --_totalLongPositions;
                    tickData.totalPos -= 1;
                    if (tickData.totalPos == 0) {
                        // we removed the last position in the tick
                        _tickBitmap.unset(_calcBitmapIndexFromTick(open.tick));
                    }
                    uint256 unadjustedTickPrice =
                        TickMath.getPriceAtTick(open.tick - int24(uint24(tickData.liquidationPenalty)) * _tickSpacing);
                    _totalExpo -= pos.totalExpo;
                    tickData.totalExpo -= pos.totalExpo;
                    _liqMultiplierAccumulator =
                        _liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * pos.totalExpo));
                }
            }
        } else if (pending.action == ProtocolAction.ValidateClosePosition && cleanup) {
            // for pending closes, the position is already out of the protocol
            LongPendingAction memory close = _toLongPendingAction(pending);
            // credit the full amount to the vault to preserve the total balance invariant (like a liquidation)
            _balanceVault += close.closeBoundedPositionValue;
        }

        // we retrieve the security deposit
        if (cleanup) {
            (bool success,) = to.call{ value: pending.securityDepositValue }("");
            if (!success) {
                revert UsdnProtocolEtherRefundFailed();
            }
        }
    }
}
