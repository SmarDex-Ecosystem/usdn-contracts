// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolCommon } from "src/interfaces/UsdnProtocol/IUsdnProtocolCommon.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolVaultImplementation is IUsdnProtocolCommon {
    function usdnPrice(uint128 currentPrice) external view returns (uint256);

    function usdnPrice(uint128 currentPrice, uint128 timestamp) external view returns (uint256);

    function getUserPendingAction(address user) external view returns (PendingAction memory action_);

    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_);

    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    function previewWithdraw(uint256 usdnShares, uint256 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_);

    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable;

    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;

    function initiateWithdrawal(
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable;

    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;
}
