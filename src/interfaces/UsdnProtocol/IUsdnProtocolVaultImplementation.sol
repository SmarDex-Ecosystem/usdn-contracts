// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { PreviousActionsData, WithdrawalPendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolVaultImplementation {
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

    function _calcWithdrawalAmountMSB(uint152 usdnShares) external pure returns (uint128 sharesMSB_);

    function _calcWithdrawalAmountLSB(uint152 usdnShares) external pure returns (uint24 sharesLSB_);

    function _checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) external view;

    function _checkImbalanceLimitDeposit(uint256 depositValue) external view;

    function _vaultAssetAvailable(uint128 currentPrice) external view returns (int256 available_);

    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) external view returns (uint256 sdexToBurn_);

    function _convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        external
        pure
        returns (PendingAction memory pendingAction_);
}
