// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IUsdnProtocolCore } from "../interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolCoreLibrary as Core } from "./libraries/UsdnProtocolCoreLibrary.sol";

abstract contract UsdnProtocolCore is UsdnProtocolStorage, IUsdnProtocolCore {
    /// @inheritdoc IUsdnProtocolCore
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable initializer {
        return Core.initialize(s, depositAmount, longAmount, desiredLiqPrice, currentPriceData);
    }

    /// @inheritdoc IUsdnProtocolCore
    function calcEMA(int256 lastFundingPerDay, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        external
        pure
        returns (int256)
    {
        return Core.calcEMA(lastFundingPerDay, secondsElapsed, emaPeriod, previousEMA);
    }

    /// @inheritdoc IUsdnProtocolCore
    function funding(uint128 timestamp)
        external
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_)
    {
        return Core.funding(s, timestamp);
    }

    /// @inheritdoc IUsdnProtocolCore
    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 expo_)
    {
        return Core.vaultTradingExpoWithFunding(s, currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolCore
    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        return Core.getActionablePendingActions(s, currentUser);
    }

    /// @inheritdoc IUsdnProtocolCore
    function getUserPendingAction(address user) external view returns (PendingAction memory action_) {
        return Core.getUserPendingAction(s, user);
    }

    /// @inheritdoc IUsdnProtocolCore
    function removeBlockedPendingAction(address validator, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core.removeBlockedPendingAction(s, validator, to);
    }

    /// @inheritdoc IUsdnProtocolCore
    function removeBlockedPendingActionNoCleanup(address validator, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core.removeBlockedPendingActionNoCleanup(s, validator, to);
    }

    /// @inheritdoc IUsdnProtocolCore
    function removeBlockedPendingAction(uint128 rawIndex, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core._removeBlockedPendingAction(s, rawIndex, to, true);
    }

    /// @inheritdoc IUsdnProtocolCore
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to)
        external
        onlyRole(CRITICAL_FUNCTIONS_ROLE)
    {
        Core._removeBlockedPendingAction(s, rawIndex, to, false);
    }
}
