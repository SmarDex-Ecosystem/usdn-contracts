// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import {
    IUsdnProtocolErrors,
    IUsdnProtocolEvents,
    ProtocolAction,
    PendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

abstract contract UsdnProtocolCore is IUsdnProtocolErrors, IUsdnProtocolEvents, UsdnProtocolStorage {
    using SafeERC20 for IERC20Metadata;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /// @notice The address that holds the minimum supply of USDN and first minimum long position.
    address public constant DEAD_ADDRESS = address(0xdead);

    uint256 constant DEFAULT_QUEUE_MAX_ITER = 10;

    /* -------------------------- Public view functions ------------------------- */

    function pnlLong(uint128 price) public view returns (int256 pnl_) {
        int256 priceDiff = int256(uint256(price)) - int256(uint256(_lastPrice));
        pnl_ = (int256(_totalExpo) * priceDiff) / int256(10 ** _assetDecimals); // same decimals as price feed
    }

    function funding(uint128 currentPrice, uint128 timestamp) public view returns (int256 fund_) {
        if (timestamp < _lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
        } else if (timestamp == _lastUpdateTimestamp) {
            return 0;
        }

        int256 secondsElapsed = int256(uint256(timestamp - _lastUpdateTimestamp));
        // we want the expo at the last update, since we are now calculating the funding since the last update
        int256 vaultExpo = _vaultTradingExpo(currentPrice);
        int256 longExpo = _longTradingExpo(currentPrice);
        int256 relative;
        if (vaultExpo > longExpo) {
            relative = vaultExpo;
        } else {
            relative = longExpo;
        }
        fund_ = ((longExpo - vaultExpo) * _fundingRatePerSecond * secondsElapsed * 100) / relative;
    }

    function fundingAsset(uint128 currentPrice, uint128 timestamp) public view returns (int256 fund_) {
        fund_ =
            (-funding(currentPrice, timestamp) * _longTradingExpo(currentPrice)) / int256(10) ** FUNDING_RATE_DECIMALS;
    }

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        available_ = _longAssetAvailable(currentPrice) - fundingAsset(currentPrice, timestamp);
    }

    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        available_ = _vaultAssetAvailable(currentPrice) + fundingAsset(currentPrice, timestamp);
    }

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256 expo_) {
        expo_ = int256(_totalExpo) - longAssetAvailableWithFunding(currentPrice, timestamp);
    }

    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 expo_)
    {
        expo_ = vaultAssetAvailableWithFunding(currentPrice, timestamp);
    }

    /* ---------------------------- Public functions ---------------------------- */

    function updateBalances(bytes calldata priceData) external payable initializedAndNonReentrant {
        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint128(block.timestamp), ProtocolAction.None, priceData
        );
        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);
    }

    /* --------------------------  Internal functions --------------------------- */

    /// @dev Available at the time of the last balances update (without taking funding into account)
    function _longAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        // Cast to int256 to optimize gas usage
        int256 totalExpo = int256(_totalExpo);
        // Cast to int256 to optimize gas usage
        int256 balanceLong = int256(_balanceLong);

        // pnlAsset = (totalExpo - balanceLong) * pnlLong * 10^assetDecimals / (totalExpo * currentPrice)
        int256 pnlAsset = ((totalExpo - balanceLong) * pnlLong(currentPrice) * int256(10) ** _assetDecimals)
            / (totalExpo * int256(uint256(currentPrice)));

        available_ = balanceLong + pnlAsset;
    }

    /// @dev Available at the time of the last balances update (without taking funding into account)
    function _vaultAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        available_ = int256(_balanceVault + _balanceLong) - _longAssetAvailable(currentPrice);
    }

    /// @dev At the time of the last balances update (without taking funding into account)
    function _longTradingExpo(uint128 currentPrice) internal view returns (int256 expo_) {
        expo_ = int256(_totalExpo) - _longAssetAvailable(currentPrice);
    }

    /// @dev At the time of the last balances update (without taking funding into account)
    function _vaultTradingExpo(uint128 currentPrice) internal view returns (int256 expo_) {
        expo_ = _vaultAssetAvailable(currentPrice);
    }

    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp) internal {
        // If the price is not fresh, do nothing
        if (timestamp <= _lastUpdateTimestamp) {
            return;
        }
        uint256 totalBalance = _balanceLong + _balanceVault;
        int256 newLongBalance = _longAssetAvailable(currentPrice) - fundingAsset(currentPrice, timestamp);
        if (newLongBalance < 0) {
            newLongBalance = 0;
        }
        int256 newVaultBalance = int256(totalBalance) - newLongBalance;
        if (newVaultBalance < 0) {
            newVaultBalance = 0;
        }
        _balanceLong = uint256(newLongBalance);
        _balanceVault = uint256(newVaultBalance);
        _lastPrice = currentPrice;
        _lastUpdateTimestamp = timestamp;
    }

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
        if (amount == 0) {
            return;
        }
        uint256 balanceBefore = _asset.balanceOf(to);
        _asset.safeTransfer(to, amount);
        if (_asset.balanceOf(to) != balanceBefore + amount) {
            revert UsdnProtocolIncompleteTransfer(to, _asset.balanceOf(to), balanceBefore + amount);
        }
    }

    /* -------------------------- Pending actions queue ------------------------- */

    function getActionablePendingAction(uint256 maxIter) public returns (PendingAction memory action_) {
        if (_pendingActionsQueue.empty()) {
            return action_;
        }
        // default max iterations
        if (maxIter == 0) {
            maxIter = DEFAULT_QUEUE_MAX_ITER;
        }

        uint256 i = 0;
        do {
            PendingAction memory candidate = _pendingActionsQueue.front();
            if (candidate.timestamp == 0) {
                // remove the stale pending action
                // slither-disable-next-line unused-return
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
        } while (++i < maxIter);
    }

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
        // slither-disable-next-line incorrect-equality
        if (pendingActionIndex == 0) {
            revert UsdnProtocolNoPendingAction();
        }

        uint128 rawIndex = uint128(pendingActionIndex - 1);
        action_ = _pendingActionsQueue.atRaw(rawIndex);

        // remove the pending action
        _pendingActionsQueue.clearAt(rawIndex);
        delete _pendingActions[user];
    }
}
