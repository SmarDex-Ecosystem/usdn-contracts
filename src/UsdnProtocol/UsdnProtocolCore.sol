// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import { IUsdnProtocolCore } from "../interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolCoreLibrary as Core } from "./libraries/UsdnProtocolCoreLibrary.sol";

abstract contract UsdnProtocolCore is
    IUsdnProtocolCore,
    InitializableReentrancyGuard,
    AccessControlDefaultAdminRulesUpgradeable
{
    /// @inheritdoc IUsdnProtocolCore
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable protocolInitializer onlyRole(DEFAULT_ADMIN_ROLE) {
        return Core.initialize(depositAmount, longAmount, desiredLiqPrice, currentPriceData);
    }

    /// @inheritdoc IUsdnProtocolCore
    function funding(uint128 timestamp)
        external
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_)
    {
        return Core.funding(timestamp);
    }
}
