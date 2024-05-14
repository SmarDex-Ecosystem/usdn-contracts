// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

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
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { UsdnProtocolActionsLibrary as actionsLib } from "src/UsdnProtocol/UsdnProtocolActionsLibrary.sol";

abstract contract UsdnProtocolActionsEntry is UsdnProtocolBaseStorage {
    function _executePendingActionOrRevert(PreviousActionsData calldata data)
        internal
        returns (uint256 securityDepositValue_)
    {
        return actionsLib._executePendingActionOrRevert(s, data);
    }

    function _executePendingAction(PreviousActionsData calldata data)
        internal
        returns (bool success_, bool executed_, uint256 securityDepositValue_)
    {
        return actionsLib._executePendingAction(s, data);
    }

    function _getPendingAction(address user) internal view returns (PendingAction memory action_, uint128 rawIndex_) {
        return actionsLib._getPendingAction(s, user);
    }

    function _addPendingAction(address user, PendingAction memory action)
        internal
        returns (uint256 securityDepositValue_)
    {
        return actionsLib._addPendingAction(s, user, action);
    }

    function _convertDepositPendingAction(DepositPendingAction memory action)
        internal
        pure
        returns (PendingAction memory pendingAction_)
    {
        return actionsLib._convertDepositPendingAction(action);
    }

    function _toDepositPendingAction(PendingAction memory action)
        internal
        pure
        returns (DepositPendingAction memory vaultAction_)
    {
        return actionsLib._toDepositPendingAction(action);
    }

    function _toWithdrawalPendingAction(PendingAction memory action)
        internal
        pure
        returns (WithdrawalPendingAction memory vaultAction_)
    {
        return actionsLib._toWithdrawalPendingAction(action);
    }

    function _toLongPendingAction(PendingAction memory action)
        internal
        pure
        returns (LongPendingAction memory longAction_)
    {
        return actionsLib._toLongPendingAction(action);
    }

    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) internal returns (LiquidationsEffects memory effects_) {
        return actionsLib._liquidatePositions(s, currentPrice, iteration, tempLongBalance, tempVaultBalance);
    }

    function _getActionablePendingAction() internal returns (PendingAction memory action_, uint128 rawIndex_) {
        return actionsLib._getActionablePendingAction(s);
    }
}
