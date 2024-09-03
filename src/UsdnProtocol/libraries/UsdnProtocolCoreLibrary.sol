// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolCore } from "../../interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../../libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolActionsVaultLibrary as ActionsVault } from "./UsdnProtocolActionsVaultLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtils as Utils } from "./UsdnProtocolUtils.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolCoreLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using SignedMath for int256;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using LibBitmap for LibBitmap.Bitmap;
    using HugeUint for HugeUint.Uint512;

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolCore}
    function initialize(
        Types.Storage storage s,
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) public {
        if (depositAmount < Constants.MIN_INIT_DEPOSIT) {
            revert IUsdnProtocolErrors.UsdnProtocolMinInitAmount(Constants.MIN_INIT_DEPOSIT);
        }
        if (longAmount < Constants.MIN_INIT_DEPOSIT) {
            revert IUsdnProtocolErrors.UsdnProtocolMinInitAmount(Constants.MIN_INIT_DEPOSIT);
        }
        // since all USDN must be minted by the protocol, we check that the total supply is 0
        IUsdn usdn = s._usdn;
        if (usdn.totalSupply() != 0) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidUsdn(address(usdn));
        }

        PriceInfo memory currentPrice =
            ActionsVault._getOraclePrice(s, Types.ProtocolAction.Initialize, block.timestamp, "", currentPriceData);

        s._lastUpdateTimestamp = uint128(block.timestamp);
        s._lastPrice = currentPrice.price.toUint128();

        (int24 tickWithPenalty, uint128 liqPriceWithoutPenalty) =
            Long._getTickFromDesiredLiqPrice(s, desiredLiqPrice, s._liquidationPenalty);
        uint128 positionTotalExpo =
            Long._calcPositionTotalExpo(longAmount, currentPrice.price.toUint128(), liqPriceWithoutPenalty);

        Vault._checkInitImbalance(s, positionTotalExpo, longAmount, depositAmount);

        Vault._createInitialDeposit(s, depositAmount, currentPrice.price.toUint128());

        Vault._createInitialPosition(s, longAmount, currentPrice.price.toUint128(), tickWithPenalty, positionTotalExpo);

        ActionsVault._refundEther(address(this).balance, payable(msg.sender));
    }

    /* -------------------------- public view functions ------------------------- */

    /// @notice See {IUsdnProtocolCore}
    function calcEMA(int256 lastFundingPerDay, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        pure
        returns (int256)
    {
        if (secondsElapsed >= emaPeriod) {
            return lastFundingPerDay;
        }

        return (
            lastFundingPerDay * Utils.toInt256(secondsElapsed)
                + previousEMA * Utils.toInt256(emaPeriod - secondsElapsed)
        ) / Utils.toInt256(emaPeriod);
    }

    /* --------------------------  public functions --------------------------- */

    /// @notice See {IUsdnProtocolCore}
    function funding(Types.Storage storage s, uint128 timestamp)
        public
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_)
    {
        (funding_, fundingPerDay_, oldLongExpo_) = _funding(s, timestamp, s._EMA);
    }

    /// @notice See {IUsdnProtocolCore}
    function vaultTradingExpoWithFunding(Types.Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 expo_)
    {
        expo_ = Vault.vaultAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    /// @notice See {IUsdnProtocolCore}
    function getActionablePendingActions(Types.Storage storage s, address currentUser)
        public
        view
        returns (Types.PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (actions_, rawIndices_);
        }
        actions_ = new Types.PendingAction[](Constants.MAX_ACTIONABLE_PENDING_ACTIONS);
        rawIndices_ = new uint128[](Constants.MAX_ACTIONABLE_PENDING_ACTIONS);
        uint256 maxIter = Constants.MAX_ACTIONABLE_PENDING_ACTIONS;
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        uint256 arrayLen = 0;
        do {
            // since `i` cannot be greater or equal to `queueLength`, there is no risk of reverting
            (Types.PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.at(i);
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
    function getUserPendingAction(Types.Storage storage s, address user)
        public
        view
        returns (Types.PendingAction memory action_)
    {
        (action_,) = _getPendingAction(s, user);
    }

    /// @notice See {IUsdnProtocolActions}
    function tickHash(int24 tick, uint256 version) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }

    /// @notice See {IUsdnProtocolCore}
    function removeBlockedPendingAction(Types.Storage storage s, address validator, address payable to) public {
        uint256 pendingActionIndex = s._pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        _removeBlockedPendingAction(s, rawIndex, to, true);
    }

    /// @notice See {IUsdnProtocolCore}
    function removeBlockedPendingActionNoCleanup(Types.Storage storage s, address validator, address payable to)
        public
    {
        uint256 pendingActionIndex = s._pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        _removeBlockedPendingAction(s, rawIndex, to, false);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Calculate the funding rate per day and the old long exposure
     * @param s The storage of the protocol
     * @param ema The EMA of the funding rate per day
     * @return fundingPerDay_ The funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals
     * @return oldLongExpo_ The old long trading expo
     */
    function _fundingPerDay(Types.Storage storage s, int256 ema)
        public
        view
        returns (int256 fundingPerDay_, int256 oldLongExpo_)
    {
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
     * @notice Calculate the funding value, funding rate value and the old long exposure
     * @dev Reverts if `timestamp` < `s._lastUpdateTimestamp`
     * @param s The storage of the protocol
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate per day
     * @return funding_ The funding (proportion of long trading expo that needs to be transferred from one side to the
     * other) with `FUNDING_RATE_DECIMALS` decimals. If positive, long side pays to vault side, otherwise it's the
     * opposite
     * @return fundingPerDay_ The funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals
     * @return oldLongExpo_ The old long trading expo
     */
    function _funding(Types.Storage storage s, uint128 timestamp, int256 ema)
        public
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_)
    {
        (fundingPerDay_, oldLongExpo_) = _fundingPerDay(s, ema);

        uint128 lastUpdateTimestamp = s._lastUpdateTimestamp;
        if (timestamp < lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }
        // subtraction can't underflow, checked above
        // conversion from uint128 to int256 is always safe
        int256 elapsedSeconds;
        unchecked {
            elapsedSeconds = Utils.toInt256(timestamp - lastUpdateTimestamp);
        }
        if (elapsedSeconds == 0) {
            return (0, fundingPerDay_, oldLongExpo_);
        }

        funding_ = fundingPerDay_.safeMul(elapsedSeconds).safeDiv(1 days);
    }

    /**
     * @notice Get the predicted value of the funding (in asset units) since the last state update for the given
     * timestamp
     * @dev If the provided timestamp is older than the last state update, the result will be zero
     * @param s The storage of the protocol
     * @param timestamp The current timestamp
     * @param ema The EMA of the funding rate
     * @return fundingAsset_ The number of asset tokens of funding (with asset decimals)
     * @return fundingPerDay_ The funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals
     */
    function _fundingAsset(Types.Storage storage s, uint128 timestamp, int256 ema)
        public
        view
        returns (int256 fundingAsset_, int256 fundingPerDay_)
    {
        int256 oldLongExpo;
        int256 fund;
        (fund, fundingPerDay_, oldLongExpo) = _funding(s, timestamp, ema);
        fundingAsset_ = fund.safeMul(oldLongExpo) / int256(10) ** Constants.FUNDING_RATE_DECIMALS;
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`
     * @param s The storage of the protocol
     * @param currentPrice The current price
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(Types.Storage storage s, uint128 currentPrice)
        public
        view
        returns (int256 available_)
    {
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
        int256 priceDiff = Utils.toInt256(newPrice) - Utils.toInt256(oldPrice);
        uint256 tradingExpo;
        // `balanceLong` is strictly inferior to `totalExpo`
        unchecked {
            tradingExpo = totalExpo - balanceLong;
        }
        int256 pnl = tradingExpo.toInt256().safeMul(priceDiff).safeDiv(Utils.toInt256(newPrice));

        available_ = balanceLong.toInt256().safeAdd(pnl);
    }

    /**
     * @notice Update the Exponential Moving Average (EMA) of the funding rate (per day)
     * @dev This function is called every time the protocol state is updated
     * @dev All required checks are done in the caller function (_applyPnlAndFunding)
     * @dev If the number of seconds elapsed is greater than or equal to the EMA period, the EMA is updated to the last
     * funding value
     * @param s The storage of the protocol
     * @param fundingPerDay The funding rate per day that was just calculated for the elapsed period
     * @param secondsElapsed The number of seconds elapsed since the last protocol action
     */
    function _updateEMA(Types.Storage storage s, int256 fundingPerDay, uint128 secondsElapsed) public {
        s._EMA = calcEMA(fundingPerDay, secondsElapsed, s._EMAPeriod, s._EMA);
    }

    /**
     * @notice Calculate the protocol fee and apply it to the funding asset amount
     * @dev The funding factor is only adjusted by the fee rate when the funding is negative (vault pays to the long
     * side)
     * @param s The storage of the protocol
     * @param fundAsset The funding asset amount to be used for the fee calculation
     * @return fee_ The absolute value of the calculated fee
     * @return fundAssetWithFee_ The updated funding asset amount after applying the fee
     */
    function _calculateFee(Types.Storage storage s, int256 fundAsset)
        public
        returns (int256 fee_, int256 fundAssetWithFee_)
    {
        int256 protocolFeeBps = Utils.toInt256(s._protocolFeeBps);
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
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `Types.WithdrawalPendingAction`
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
    function _calcBitmapIndexFromTick(Types.Storage storage s, int24 tick) public view returns (uint256 index_) {
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
     * @return data_ The data containing the temporary long balance, the temporary vault
     * balance, the last price and a flag indicating if the price is recent
     */
    function _applyPnlAndFunding(Types.Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        returns (Types.ApplyPnlAndFundingData memory data_)
    {
        int256 fundAsset;
        {
            // cache variable for optimization
            uint128 lastUpdateTimestamp = s._lastUpdateTimestamp;
            // if the price is not fresh, do nothing
            if (timestamp <= lastUpdateTimestamp) {
                return Types.ApplyPnlAndFundingData({
                    isPriceRecent: timestamp == lastUpdateTimestamp,
                    tempLongBalance: s._balanceLong.toInt256(),
                    tempVaultBalance: s._balanceVault.toInt256(),
                    lastPrice: s._lastPrice
                });
            }

            // calculate the funding
            int256 fundingPerDay;
            (fundAsset, fundingPerDay) = _fundingAsset(s, timestamp, s._EMA);

            s._lastFundingPerDay = fundingPerDay;
            emit IUsdnProtocolEvents.LastFundingPerDayUpdated(fundingPerDay, timestamp);

            // update the funding EMA (mutates the storage)
            _updateEMA(s, fundingPerDay, timestamp - lastUpdateTimestamp);
        }

        // take protocol fee on the funding value
        (int256 fee, int256 fundAssetWithFee) = _calculateFee(s, fundAsset);

        // we subtract the fee from the total balance
        int256 totalBalance = s._balanceLong.toInt256();
        totalBalance = totalBalance.safeAdd(s._balanceVault.toInt256()).safeSub(fee);
        // calculate new balances (for now, any bad debt has not been repaid, balances could become negative)

        if (fundAsset > 0) {
            // in case of positive funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the vault balance will be incremented
            // only by the funding amount minus the fee amount
            data_.tempLongBalance = _longAssetAvailable(s, currentPrice).safeSub(fundAsset);
        } else {
            // in case of negative funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the long balance will be incremented
            // only by the funding amount minus the fee amount
            data_.tempLongBalance = _longAssetAvailable(s, currentPrice).safeSub(fundAssetWithFee);
        }
        data_.tempVaultBalance = totalBalance.safeSub(data_.tempLongBalance);

        // update state variables
        s._lastPrice = currentPrice;
        data_.lastPrice = currentPrice;
        s._lastUpdateTimestamp = timestamp;

        data_.isPriceRecent = true;
    }

    /**
     * @notice Convert a `Types.PendingAction` to a `Types.DepositPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted deposit pending action
     */
    function _toDepositPendingAction(Types.PendingAction memory action)
        public
        pure
        returns (Types.DepositPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.PendingAction` to a `Types.WithdrawalPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted withdrawal pending action
     */
    function _toWithdrawalPendingAction(Types.PendingAction memory action)
        public
        pure
        returns (Types.WithdrawalPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.PendingAction` to a `Types.LongPendingAction`
     * @param action An untyped pending action
     * @return longAction_ The converted long pending action
     */
    function _toLongPendingAction(Types.PendingAction memory action)
        public
        pure
        returns (Types.LongPendingAction memory longAction_)
    {
        assembly {
            longAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.DepositPendingAction` to a `Types.PendingAction`
     * @param action A deposit pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertDepositPendingAction(Types.DepositPendingAction memory action)
        public
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.WithdrawalPendingAction` to a `Types.PendingAction`
     * @param action A withdrawal pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertWithdrawalPendingAction(Types.WithdrawalPendingAction memory action)
        public
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `Types.LongPendingAction` to a `Types.PendingAction`
     * @param action A long pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertLongPendingAction(Types.LongPendingAction memory action)
        public
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice This is the mutating version of `getActionablePendingAction`, where empty items at the front of the list
     * are removed
     * @return action_ The first actionable pending action if any, otherwise a struct with all fields set to zero and
     * Types.ProtocolAction.None
     * @return rawIndex_ The raw index in the queue for the returned pending action, or zero
     */
    function _getActionablePendingAction(Types.Storage storage s)
        public
        returns (Types.PendingAction memory action_, uint128 rawIndex_)
    {
        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (action_, rawIndex_);
        }
        uint256 maxIter = Constants.MAX_ACTIONABLE_PENDING_ACTIONS;
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        do {
            // since we will never call `front` more than `queueLength` times, there is no risk of reverting
            (Types.PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.front();
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
    function _removeStalePendingAction(Types.Storage storage s, address user)
        public
        returns (uint256 securityDepositValue_)
    {
        if (s._pendingActions[user] == 0) {
            return 0;
        }
        (Types.PendingAction memory action, uint128 rawIndex) = _getPendingAction(s, user);
        // the position is only at risk of being liquidated while pending if it is an open position action
        if (action.action == Types.ProtocolAction.ValidateOpenPosition) {
            Types.LongPendingAction memory openAction = _toLongPendingAction(action);
            uint256 version = s._tickVersion[openAction.tick];
            if (version != openAction.tickVersion) {
                securityDepositValue_ = openAction.securityDepositValue;
                // the position was liquidated while pending
                // remove the stale pending action
                s._pendingActionsQueue.clearAt(rawIndex);
                delete s._pendingActions[user];
                emit IUsdnProtocolEvents.StalePendingActionRemoved(
                    user,
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
     * @notice Add a pending action to the queue
     * @dev This reverts if there is already a pending action for this user
     * @param s The storage of the protocol
     * @param user The user's address
     * @param action The pending action struct
     * @return amountToRefund_ The security deposit value of the stale pending action
     */
    function _addPendingAction(Types.Storage storage s, address user, Types.PendingAction memory action)
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
     * @dev To check for the presence of a pending action, compare `action_.action` to `Types.ProtocolAction.None`. There
     * is
     * a pending action only if the action is different from `Types.ProtocolAction.None`
     * @param s The storage of the protocol
     * @param user The user's address
     * @return action_ The pending action struct if any, otherwise a zero-initialized struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingAction(Types.Storage storage s, address user)
        public
        view
        returns (Types.PendingAction memory action_, uint128 rawIndex_)
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
    function _getPendingActionOrRevert(Types.Storage storage s, address user)
        public
        view
        returns (Types.PendingAction memory action_, uint128 rawIndex_)
    {
        (action_, rawIndex_) = _getPendingAction(s, user);
        if (action_.action == Types.ProtocolAction.None) {
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
    }

    /**
     * @notice Clear the pending action for a user
     * @param s The storage of the protocol
     * @param user The user's address
     * @param rawIndex The rawIndex of the pending action in the queue
     */
    function _clearPendingAction(Types.Storage storage s, address user, uint128 rawIndex) public {
        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Remove a stuck pending action and perform the minimal amount of cleanup necessary
     * @dev This function should only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something reverting unexpectedly
     * The caller must wait at least 1 hour after the validation deadline to call this function. This is to give the
     * chance to normal users to validate the action if possible
     * @param s The storage of the protocol
     * @param rawIndex The raw index of the pending action in the queue
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn)
     * @param cleanup If `true`, will attempt to perform more cleanup at the risk of reverting. Always try `true` first
     */
    function _removeBlockedPendingAction(Types.Storage storage s, uint128 rawIndex, address payable to, bool cleanup)
        public
    {
        Types.PendingAction memory pending = s._pendingActionsQueue.atRaw(rawIndex);
        if (block.timestamp < pending.timestamp + s._validationDeadline + 1 hours) {
            revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
        }
        delete s._pendingActions[pending.validator];
        s._pendingActionsQueue.clearAt(rawIndex);
        if (pending.action == Types.ProtocolAction.ValidateDeposit && cleanup) {
            // for pending deposits, we send back the locked assets
            Types.DepositPendingAction memory deposit = _toDepositPendingAction(pending);
            s._pendingBalanceVault -= Utils.toInt256(deposit.amount);
            address(s._asset).safeTransfer(to, deposit.amount);
        } else if (pending.action == Types.ProtocolAction.ValidateWithdrawal && cleanup) {
            // for pending withdrawals, we send the locked USDN
            Types.WithdrawalPendingAction memory withdrawal = _toWithdrawalPendingAction(pending);
            uint256 shares = _mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);
            uint256 pendingAmount =
                FixedPointMathLib.fullMulDiv(shares, withdrawal.balanceVault, withdrawal.usdnTotalShares);
            s._pendingBalanceVault += pendingAmount.toInt256();
            s._usdn.transferShares(to, shares);
        } else if (pending.action == Types.ProtocolAction.ValidateOpenPosition) {
            // for pending opens, we need to remove the position
            Types.LongPendingAction memory open = _toLongPendingAction(pending);
            (bytes32 tHash, uint256 tickVersion) = _tickHash(s, open.tick);
            if (tickVersion == open.tickVersion) {
                // we only need to modify storage if the pos was not liquidated already

                int256 posValue;
                if (cleanup) {
                    posValue = Long.getPositionValue(
                        s,
                        Types.PositionId(open.tick, open.tickVersion, open.index),
                        s._lastPrice,
                        s._lastUpdateTimestamp
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
                    if (tickData.totalPos == 0) {
                        // we removed the last position in the tick
                        s._tickBitmap.unset(_calcBitmapIndexFromTick(s, open.tick));
                    }
                    uint256 unadjustedTickPrice =
                        TickMath.getPriceAtTick(Utils.calcTickWithoutPenalty(open.tick, tickData.liquidationPenalty));
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
            Types.LongPendingAction memory close = _toLongPendingAction(pending);
            // credit the full amount to the vault to preserve the total balance invariant (like a liquidation)
            s._balanceVault += close.closeBoundedPositionValue;
        }

        // we retrieve the security deposit
        if (cleanup) {
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = to.call{ value: pending.securityDepositValue }("");
            if (!success) {
                revert IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed();
            }
        }
    }

    /**
     * @notice Function to calculate the hash and version of a given tick
     * @param s The storage of the protocol
     * @param tick The tick
     * @return hash_ The hash of the tick
     * @return version_ The version of the tick
     */
    function _tickHash(Types.Storage storage s, int24 tick) public view returns (bytes32 hash_, uint256 version_) {
        version_ = s._tickVersion[tick];
        hash_ = tickHash(tick, version_);
    }

    /// @notice See {IUsdnProtocolLong}
    function longAssetAvailableWithFunding(Types.Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }

        (int256 fundAsset,) = _fundingAsset(s, timestamp, s._EMA);

        if (fundAsset > 0) {
            available_ = _longAssetAvailable(s, currentPrice).safeSub(fundAsset);
        } else {
            int256 fee = fundAsset * Utils.toInt256(s._protocolFeeBps) / int256(Constants.BPS_DIVISOR);
            // fees have the same sign as fundAsset (negative here), so we need to sub them
            available_ = _longAssetAvailable(s, currentPrice).safeSub(fundAsset - fee);
        }

        int256 totalBalance = (s._balanceLong + s._balanceVault).toInt256();
        if (available_ > totalBalance) {
            available_ = totalBalance;
        }
    }

    /// @notice See {IUsdnProtocolLong}
    function longTradingExpoWithFunding(Types.Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 expo_)
    {
        expo_ = s._totalExpo.toInt256().safeSub(longAssetAvailableWithFunding(s, currentPrice, timestamp));
    }
}
