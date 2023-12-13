// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { IUsdnProtocolErrors, IUsdnProtocolEvents, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

abstract contract UsdnProtocolCore is IUsdnProtocolErrors, IUsdnProtocolEvents, UsdnProtocolStorage {
    using SafeERC20 for IERC20Metadata;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    uint256 constant QUEUE_MAX_ITER = 10;

    function _retrieveAssetsAndCheckBalance(address from, uint256 amount) internal {
        uint256 balanceBefore = _asset.balanceOf(address(this));
        _asset.safeTransferFrom(from, address(this), amount);
        if (_asset.balanceOf(address(this)) != balanceBefore + amount) {
            revert UsdnProtocolIncompleteTransfer(
                address(this), _asset.balanceOf(address(this)), balanceBefore + amount
            );
        }
    }

    function _distributeAssetsAndCheckBalance(address to, uint256 amount) internal {
        uint256 balanceBefore = _asset.balanceOf(to);
        if (amount > 0) {
            _asset.safeTransfer(to, amount);
            if (_asset.balanceOf(to) != balanceBefore + amount) {
                revert UsdnProtocolIncompleteTransfer(to, _asset.balanceOf(to), balanceBefore + amount);
            }
        }
    }

    function longAssetAvailable(uint128 currentPrice) public view returns (int256 available_) {
        // TODO
    }

    function vaultAssetAvailable(uint128 currentPrice) public view returns (int256 available_) {
        available_ = int256(_balanceVault + _balanceLong) - longAssetAvailable(currentPrice);
    }

    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp) internal {
        // If the price is not fresh, do nothing
        if (timestamp <= _lastUpdateTimestamp) {
            return;
        }
        // silence unused variable and visibility warnings
        currentPrice;
        _balanceVault = _balanceVault;
        // TODO: apply PnL and funding
    }

    /* -------------------------- Pending actions queue ------------------------- */

    function _addPendingAction(address user, PendingAction memory action) internal {
        if (_pendingActions[user] > 0) {
            revert UsdnProtocolPendingAction();
        }
        // Add the action to the queue
        uint128 rawIndex = _pendingActionsQueue.pushBack(action);
        // Store the index shifted by one, so that zero means no pending action
        _pendingActions[user] = uint256(rawIndex) + 1;
    }

    function _getAndClearPendingAction(address user) internal returns (PendingAction memory action_) {
        uint256 pendingActionIndex = _pendingActions[user];
        if (pendingActionIndex == 0) {
            revert UsdnProtocolNoPendingAction();
        }

        uint128 rawIndex = uint128(pendingActionIndex - 1);
        action_ = _pendingActionsQueue.atRaw(rawIndex);

        // remove the pending action
        _pendingActionsQueue.clearAt(rawIndex);
        delete _pendingActions[user];
    }

    function getActionablePendingAction() public returns (PendingAction memory action_) {
        if (_pendingActionsQueue.empty()) {
            return action_;
        }

        uint256 i = 0;
        do {
            PendingAction memory candidate = _pendingActionsQueue.front();
            if (candidate.timestamp == 0) {
                // remove the stale pending action
                _pendingActionsQueue.popFront();
                // if the queue is empty, return
                if (_pendingActionsQueue.empty()) {
                    return action_;
                }
                // otherwise, try the next one
                continue;
            } else if (candidate.timestamp + _validationDeadline < block.timestamp) {
                // we found an actionable pending action
                return candidate;
            } else {
                // the first pending action is not actionable
                return action_;
            }
        } while (++i < QUEUE_MAX_ITER);
    }
}
