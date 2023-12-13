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

    function _retrieveAssetsAndCheckBalance(address _from, uint256 _amount) internal {
        uint256 _balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(_from, address(this), _amount);
        if (asset.balanceOf(address(this)) != _balanceBefore + _amount) {
            revert UsdnProtocolIncompleteTransfer(
                address(this), asset.balanceOf(address(this)), _balanceBefore + _amount
            );
        }
    }

    function _distributeAssetsAndCheckBalance(address _to, uint256 _amount) internal {
        uint256 _balanceBefore = asset.balanceOf(_to);
        if (_amount > 0) {
            asset.safeTransfer(_to, _amount);
            if (asset.balanceOf(_to) != _balanceBefore + _amount) {
                revert UsdnProtocolIncompleteTransfer(_to, asset.balanceOf(_to), _balanceBefore + _amount);
            }
        }
    }

    function longAssetAvailable(uint128 _currentPrice) public view returns (int256 available_) {
        // TODO
    }

    function vaultAssetAvailable(uint128 _currentPrice) public view returns (int256 available_) {
        available_ = int256(balanceVault + balanceLong) - longAssetAvailable(_currentPrice);
    }

    function _applyPnlAndFunding(uint128 _currentPrice, uint128 _timestamp) internal {
        // If the price is not fresh, do nothing
        if (_timestamp <= lastUpdateTimestamp) {
            return;
        }
        // silence unused variable and visibility warnings
        _currentPrice;
        balanceVault = balanceVault;
        // TODO: apply PnL and funding
    }

    /* -------------------------- Pending actions queue ------------------------- */

    function _addPendingAction(address _user, PendingAction memory _action) internal {
        if (pendingActions[_user] > 0) {
            revert UsdnProtocolPendingAction();
        }
        // Add the action to the queue
        uint128 _rawIndex = pendingActionsQueue.pushBack(_action);
        // Store the index shifted by one, so that zero means no pending action
        pendingActions[_user] = uint256(_rawIndex) + 1;
    }

    function _getAndClearPendingAction(address _user) internal returns (PendingAction memory action_) {
        uint256 _pendingActionIndex = pendingActions[_user];
        if (_pendingActionIndex == 0) {
            revert UsdnProtocolNoPendingAction();
        }

        uint128 _rawIndex = uint128(_pendingActionIndex - 1);
        action_ = pendingActionsQueue.atRaw(_rawIndex);

        // remove the pending action
        pendingActionsQueue.clearAt(_rawIndex);
        delete pendingActions[_user];
    }

    function getActionablePendingAction() public returns (PendingAction memory action_) {
        if (pendingActionsQueue.empty()) {
            return action_;
        }

        uint256 i = 0;
        do {
            PendingAction memory _candidate = pendingActionsQueue.front();
            if (_candidate.timestamp == 0) {
                // remove the stale pending action
                pendingActionsQueue.popFront();
                // if the queue is empty, return
                if (pendingActionsQueue.empty()) {
                    return action_;
                }
                // otherwise, try the next one
                continue;
            } else if (_candidate.timestamp + validationDeadline < block.timestamp) {
                // we found an actionable pending action
                return _candidate;
            } else {
                // the first pending action is not actionable
                return action_;
            }
        } while (++i < QUEUE_MAX_ITER);
    }
}
