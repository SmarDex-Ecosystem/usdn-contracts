// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { PendingAction } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolCoreLibrary as lib } from "./UsdnProtocolCoreLibrary.sol";

abstract contract UsdnProtocolCoreEntry is UsdnProtocolBaseStorage {
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        pure
        returns (int256)
    {
        return lib.calcEMA(lastFunding, secondsElapsed, emaPeriod, previousEMA);
    }

    function funding(uint128 timestamp) external view returns (int256 fund_, int256 oldLongExpo_) {
        return lib.funding(s, timestamp);
    }

    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 expo_)
    {
        return lib.vaultTradingExpoWithFunding(s, currentPrice, timestamp);
    }

    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        return lib.getActionablePendingActions(s, currentUser);
    }

    function getUserPendingAction(address user) external view returns (PendingAction memory action_) {
        return lib.getUserPendingAction(s, user);
    }

    // / @inheritdoc IUsdnProtocol
    function removeBlockedPendingAction(uint128 rawIndex, address payable to) external onlyOwner {
        lib._removeBlockedPendingAction(s, rawIndex, to, true);
    }

    // / @inheritdoc IUsdnProtocol
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to) external onlyOwner {
        lib._removeBlockedPendingAction(s, rawIndex, to, false);
    }
}
