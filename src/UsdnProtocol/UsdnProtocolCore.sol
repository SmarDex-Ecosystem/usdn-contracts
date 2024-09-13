// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

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
    ) external payable protocolInitializer onlyRole(DEFAULT_ADMIN_ROLE) {
        return Core.initialize(s, depositAmount, longAmount, desiredLiqPrice, currentPriceData);
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
    function getUserPendingAction(address user) external view returns (PendingAction memory action_) {
        return Core.getUserPendingAction(s, user);
    }

    /// @inheritdoc IUsdnProtocolCore
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 available_)
    {
        return Core.longAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnProtocolCore
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256 expo_) {
        return Core.longTradingExpoWithFunding(s, currentPrice, timestamp);
    }
}
