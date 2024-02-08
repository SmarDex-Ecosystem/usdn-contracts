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
    VaultPendingAction,
    LongPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

abstract contract UsdnProtocolCore is IUsdnProtocolCore, UsdnProtocolStorage {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using SignedMath for int256;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /// @inheritdoc IUsdnProtocolCore
    address public constant DEAD_ADDRESS = address(0xdead);

    /// @inheritdoc IUsdnProtocolCore
    uint256 public constant DEFAULT_QUEUE_MAX_ITER = 10;

    /* -------------------------- Public view functions ------------------------- */

    /// @inheritdoc IUsdnProtocolCore
    function getLiquidationMultiplier(uint128 currentPrice, uint128 timestamp) external view returns (uint256) {
        if (timestamp <= _lastUpdateTimestamp) {
            return _liquidationMultiplier;
        }

        (int256 fund, int256 oldLongExpo, int256 oldVaultExpo) = funding(currentPrice, timestamp);
        return _getLiquidationMultiplier(fund, oldLongExpo, oldVaultExpo, _liquidationMultiplier);
    }

    /// @inheritdoc IUsdnProtocolCore
    function funding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 fund_, int256 longExpo_, int256 vaultExpo_)
    {
        vaultExpo_ = _vaultTradingExpo(currentPrice);
        longExpo_ = _longTradingExpo(currentPrice);
        if (timestamp < _lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
            // slither-disable-next-line incorrect-equality
        } else if (timestamp == _lastUpdateTimestamp) {
            return (0, longExpo_, vaultExpo_);
        }

        int256 secondsElapsed = _toInt256(timestamp - _lastUpdateTimestamp);
        // we want the expo at the last update, since we are now calculating the funding since the last update
        int256 relative;
        if (vaultExpo_ > longExpo_) {
            relative = vaultExpo_;
        } else {
            relative = longExpo_;
        }
        // avoid division by zero
        if (relative == 0) {
            return (0, longExpo_, vaultExpo_);
        }
        fund_ = longExpo_.safeSub(vaultExpo_).safeMul(_fundingRatePerSecond * secondsElapsed * 100).safeDiv(relative);
    }

    /// @inheritdoc IUsdnProtocolCore
    function fundingAsset(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 fund_, int256 longExpo_, int256 vaultExpo_)
    {
        (fund_, longExpo_, vaultExpo_) = funding(currentPrice, timestamp);
        fund_ = fund_.safeMul(longExpo_) / int256(10) ** FUNDING_RATE_DECIMALS;
    }

    /// @inheritdoc IUsdnProtocolCore
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        (int256 fund,,) = fundingAsset(currentPrice, timestamp);
        available_ = _longAssetAvailable(currentPrice).safeSub(fund);
    }

    /// @inheritdoc IUsdnProtocolCore
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        (int256 fund,,) = fundingAsset(currentPrice, timestamp);
        available_ = _vaultAssetAvailable(currentPrice).safeAdd(fund);
    }

    /// @inheritdoc IUsdnProtocolCore
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256 expo_) {
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
    function getActionablePendingAction(uint256 maxIter) external view returns (PendingAction memory action_) {
        uint256 queueLength = _pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return action_;
        }
        // default max iterations
        if (maxIter == 0) {
            maxIter = DEFAULT_QUEUE_MAX_ITER;
        }
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        do {
            // Since `i` cannot be greater or equal to `queueLength`, there is no risk of reverting
            PendingAction memory candidate = _pendingActionsQueue.at(i);
            // gas optimization
            unchecked {
                i++;
            }
            // If the msg.sender is equal to the user of the pending action, then the pending action is not actionable
            // by this user (it will get validated automatically by their action). And so we need to return the next
            // item in the queue so that they can validate a third-party pending action (if any).
            if (candidate.timestamp == 0 || candidate.user == msg.sender) {
                // try the next one
                continue;
            } else if (candidate.timestamp + _validationDeadline < block.timestamp) {
                // we found an actionable pending action
                return candidate;
            }
            // the first pending action is not actionable
            return action_;
        } while (i < maxIter);
    }

    /* --------------------------  Internal functions --------------------------- */

    function _getLiquidationMultiplier(
        int256 fund,
        int256 oldLongExpo,
        int256 oldVaultExpo,
        uint256 liquidationMultiplier
    ) internal pure returns (uint256 multiplier_) {
        multiplier_ = liquidationMultiplier;

        if (oldLongExpo >= oldVaultExpo) {
            // newMultiplier = oldMultiplier * (1 + funding)
            if (fund > 0) {
                multiplier_ += FixedPointMathLib.fullMulDiv(multiplier_, uint256(fund), 10 ** FUNDING_RATE_DECIMALS);
            } else {
                multiplier_ -= FixedPointMathLib.fullMulDiv(multiplier_, uint256(-fund), 10 ** FUNDING_RATE_DECIMALS);
            }
        } else {
            // newMultiplier = oldMultiplier * (1 + funding * (oldLongExpo / _balanceVault))
            if (fund > 0) {
                multiplier_ += FixedPointMathLib.fullMulDiv(
                    multiplier_ * uint256(fund),
                    uint256(oldLongExpo),
                    uint256(oldVaultExpo) * 10 ** FUNDING_RATE_DECIMALS
                );
            } else {
                multiplier_ -= FixedPointMathLib.fullMulDiv(
                    multiplier_ * uint256(-fund),
                    uint256(oldLongExpo),
                    uint256(oldVaultExpo) * 10 ** FUNDING_RATE_DECIMALS
                );
            }
        }
    }

    /**
     * @notice Calculate the PnL in dollars of the long side, considering the overall total expo and change in price.
     * @dev TODO: not used right now, maybe make external for front-end?
     * @param totalExpo The total exposure of the long side
     * @param newPrice The new price
     * @param oldPrice The old price
     */
    function _pnlLong(uint256 totalExpo, uint128 newPrice, uint128 oldPrice) internal view returns (int256 pnl_) {
        int256 priceDiff = _toInt256(newPrice) - _toInt256(oldPrice);
        pnl_ = totalExpo.toInt256().safeMul(priceDiff) / int256(10 ** _assetDecimals); // same decimals as price feed
    }

    /**
     * @notice Calculate the PnL in asset units of the long side, considering the overall total expo and change in
     * price.
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     */
    function _pnlAsset(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 pnl_)
    {
        int256 priceDiff = _toInt256(newPrice) - _toInt256(oldPrice);
        pnl_ = totalExpo.toInt256().safeSub(balanceLong.toInt256()).safeMul(priceDiff).safeDiv(_toInt256(newPrice));
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @param currentPrice The current price
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`.
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
     */
    function _longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 available_)
    {
        // Avoid division by zero
        // slither-disable-next-line incorrect-equality
        if (totalExpo == 0) {
            return 0;
        }

        available_ = balanceLong.toInt256().safeAdd(_pnlAsset(totalExpo, balanceLong, newPrice, oldPrice));
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account).
     * @param currentPrice Current price
     */
    function _vaultAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        available_ = _vaultAssetAvailable(_totalExpo, _balanceVault, _balanceLong, currentPrice, _lastPrice);
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account).
     * @param totalExpo the total expo
     * @param balanceVault the (old) balance of the vault
     * @param balanceLong the (old) balance of the long side
     * @param newPrice the new price
     * @param oldPrice the old price when the old balances were updated
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
        if (newLongBalance < 0) {
            newLongBalance = 0;
        }
        available_ = totalBalance.safeSub(newLongBalance);
        if (available_ < 0) {
            available_ = 0;
        }
    }

    /// @dev At the time of the last balances update (without taking funding into account)
    function _longTradingExpo(uint128 currentPrice) internal view returns (int256 expo_) {
        expo_ = _totalExpo.toInt256().safeSub(_longAssetAvailable(currentPrice));
    }

    /// @dev At the time of the last balances update (without taking funding into account)
    function _vaultTradingExpo(uint128 currentPrice) internal view returns (int256 expo_) {
        expo_ = _vaultAssetAvailable(currentPrice);
    }

    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp) internal returns (bool priceUpdated_) {
        // If the price is not fresh, do nothing
        if (timestamp <= _lastUpdateTimestamp) {
            return false;
        }

        (int256 fund, int256 oldLongExpo, int256 oldVaultExpo) = funding(currentPrice, timestamp);
        (int256 fundAsset,,) = fundingAsset(currentPrice, timestamp);

        int256 totalBalance = _balanceLong.toInt256().safeAdd(_balanceVault.toInt256());
        int256 newLongBalance = _longAssetAvailable(currentPrice).safeSub(fundAsset);
        if (newLongBalance < 0) {
            newLongBalance = 0;
        }
        int256 newVaultBalance = totalBalance.safeSub(newLongBalance);
        if (newVaultBalance < 0) {
            newVaultBalance = 0;
        }
        _balanceLong = uint256(newLongBalance);
        _balanceVault = uint256(newVaultBalance);
        _lastPrice = currentPrice;
        _lastUpdateTimestamp = timestamp;
        _liquidationMultiplier = _getLiquidationMultiplier(fund, oldLongExpo, oldVaultExpo, _liquidationMultiplier);

        priceUpdated_ = true;
    }

    function _retrieveAssetsAndCheckBalance(address from, uint256 amount) internal {
        uint256 balanceBefore = _asset.balanceOf(address(this));
        _asset.safeTransferFrom(from, address(this), amount);
        uint256 expectedBalance = balanceBefore + amount;
        if (_asset.balanceOf(address(this)) != expectedBalance) {
            revert UsdnProtocolIncompleteTransfer(address(this), _asset.balanceOf(address(this)), expectedBalance);
        }
    }

    function _distributeAssetsAndCheckBalance(address to, uint256 amount) internal {
        // slither-disable-next-line incorrect-equality
        if (amount == 0) {
            return;
        }
        uint256 balanceBefore = _asset.balanceOf(to);
        _asset.safeTransfer(to, amount);
        uint256 expectedBalance = balanceBefore + amount;
        if (_asset.balanceOf(to) != expectedBalance) {
            revert UsdnProtocolIncompleteTransfer(to, _asset.balanceOf(to), expectedBalance);
        }
    }

    function _toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    function _tickHash(int24 tick) internal view returns (bytes32 hash_, uint256 version_) {
        version_ = _tickVersion[tick];
        hash_ = keccak256(abi.encodePacked(tick, version_));
    }

    /* -------------------------- Pending actions queue ------------------------- */

    /**
     * @notice Convert a `PendingAction` to a `VaultPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted vault pending action
     */
    function _toVaultPendingAction(PendingAction memory action)
        internal
        pure
        returns (VaultPendingAction memory vaultAction_)
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
     * @notice Convert a `VaultPendingAction` to a `PendingAction`
     * @param action A vault pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertVaultPendingAction(VaultPendingAction memory action)
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
     * are removed.
     * @param maxIter The maximum number of iterations to find the first initialized item
     * @return action_ The pending action if any, otherwise a struct with all fields set to zero and ProtocolAction.None
     */
    function _getActionablePendingAction(uint256 maxIter) internal returns (PendingAction memory action_) {
        uint256 queueLength = _pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return action_;
        }
        // default max iterations
        if (maxIter == 0) {
            maxIter = DEFAULT_QUEUE_MAX_ITER;
        }
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        do {
            // Since we will never call `front` more than `queueLength` times, there is no risk of reverting
            PendingAction memory candidate = _pendingActionsQueue.front();
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
                return candidate;
            }
            // the first pending action is not actionable
            return action_;
        } while (i < maxIter);
    }

    /**
     * @notice Remove the pending action from the queue if its tick version doesn't match the current tick version
     * @dev This is only applicable to `ValidateOpenPosition` pending actions
     * @param user The user address
     */
    function _removeStalePendingAction(address user) internal {
        uint256 pendingActionIndex = _pendingActions[user];
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            return;
        }
        (PendingAction memory action, uint128 rawIndex) = _getPendingAction(user, false); // do not clear
        // the position is only at risk of being liquidated while pending if it is an open position action
        // slither-disable-next-line incorrect-equality
        if (action.action == ProtocolAction.ValidateOpenPosition) {
            LongPendingAction memory openAction = _toLongPendingAction(action);
            (, uint256 version) = _tickHash(openAction.tick);
            if (version != openAction.tickVersion) {
                // the position was liquidated while pending
                // remove the stale pending action
                _pendingActionsQueue.clearAt(rawIndex);
                delete _pendingActions[user];
                emit StalePendingActionRemoved(user, openAction.tick, openAction.tickVersion, openAction.index);
            }
        }
    }

    /**
     * @notice Add a pending action to the queue
     * @dev This reverts if there is already a pending action for this user
     * @param user The user address
     * @param action The pending action struct
     */
    function _addPendingAction(address user, PendingAction memory action) internal {
        _removeStalePendingAction(user); // check if there is a pending action that was liquidated and remove it
        if (_pendingActions[user] > 0) {
            revert UsdnProtocolPendingAction();
        }
        // Add the action to the queue
        uint128 rawIndex = _pendingActionsQueue.pushBack(action);
        // Store the index shifted by one, so that zero means no pending action
        _pendingActions[user] = uint256(rawIndex) + 1;
    }

    /**
     * @notice Get the pending action for a user and optionally pop it from the queue
     * @param user The user address
     * @param clear Whether to pop the pending action from the queue or leave it there
     * @return action_ The pending action struct
     * @return rawIndex_ The raw index of the pending action in the queue
     */
    function _getPendingAction(address user, bool clear)
        internal
        returns (PendingAction memory action_, uint128 rawIndex_)
    {
        uint256 pendingActionIndex = _pendingActions[user];
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            revert UsdnProtocolNoPendingAction();
        }

        rawIndex_ = uint128(pendingActionIndex - 1);
        action_ = _pendingActionsQueue.atRaw(rawIndex_);

        if (clear) {
            // remove the pending action
            _pendingActionsQueue.clearAt(rawIndex_);
            delete _pendingActions[user];
        }
    }
}
