// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IUsdnProtocolCore } from "./../interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { PendingAction } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolCoreLibrary as lib } from "./UsdnProtocolCoreLibrary.sol";

abstract contract UsdnProtocolCoreEntry is UsdnProtocolBaseStorage, IUsdnProtocolCore {
    /// @inheritdoc IUsdnProtocolCore
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) public payable initializer {
        return lib.initialize(s, depositAmount, longAmount, desiredLiqPrice, currentPriceData);
    }

    /// @inheritdoc IUsdnProtocolCore
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        pure
        returns (int256)
    {
        return lib.calcEMA(lastFunding, secondsElapsed, emaPeriod, previousEMA);
    }

    /// @inheritdoc IUsdnProtocolCore
    function funding(uint128 timestamp) external view returns (int256 fund_, int256 oldLongExpo_) {
        return lib.funding(s, timestamp);
    }

    /// @inheritdoc IUsdnProtocolCore
    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 expo_)
    {
        return lib.vaultTradingExpoWithFunding(s, currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolCore
    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        return lib.getActionablePendingActions(s, currentUser);
    }

    /// @inheritdoc IUsdnProtocolCore
    function getUserPendingAction(address user) external view returns (PendingAction memory action_) {
        return lib.getUserPendingAction(s, user);
    }

    /// @inheritdoc IUsdnProtocolCore
    function removeBlockedPendingAction(uint128 rawIndex, address payable to) external onlyOwner {
        lib._removeBlockedPendingAction(s, rawIndex, to, true);
    }

    /// @inheritdoc IUsdnProtocolCore
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to) external onlyOwner {
        lib._removeBlockedPendingAction(s, rawIndex, to, false);
    }
}
