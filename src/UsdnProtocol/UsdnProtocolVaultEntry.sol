// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    PendingAction,
    PreviousActionsData,
    WithdrawalPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from "src/UsdnProtocol/UsdnProtocolVaultLibrary.sol";

abstract contract UsdnProtocolVaultEntry is UsdnProtocolBaseStorage, InitializableReentrancyGuard {
    using SafeCast for int256;
    using SafeCast for uint256;

    function usdnPrice(uint128 currentPrice, uint128 timestamp) public view returns (uint256 price_) {
        return vaultLib.usdnPrice(s, currentPrice, timestamp);
    }

    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        return vaultLib.usdnPrice(s, currentPrice);
    }

    function getUserPendingAction(address user) external view returns (PendingAction memory action_) {
        return vaultLib.getUserPendingAction(s, user);
    }

    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        return vaultLib.getActionablePendingActions(s, currentUser);
    }

    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 expo_)
    {
        return vaultLib.vaultTradingExpoWithFunding(s, currentPrice, timestamp);
    }

    /**
     * @notice Calculate an estimation of assets received when withdrawing
     * @param usdnShares The amount of USDN shares
     * @param price The price of the asset
     * @param timestamp The timestamp of the operation
     * @return assetExpected_ The expected amount of asset to be received
     */
    function previewWithdraw(uint256 usdnShares, uint256 price, uint128 timestamp)
        public
        view
        returns (uint256 assetExpected_)
    {
        return vaultLib.previewWithdraw(s, usdnShares, price, timestamp);
    }

    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        return vaultLib.vaultAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        vaultLib.initiateDeposit(s, amount, currentPriceData, previousActionsData, to);
    }

    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        vaultLib.validateDeposit(s, depositPriceData, previousActionsData);
    }

    function initiateWithdrawal(
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        vaultLib.initiateWithdrawal(s, usdnShares, currentPriceData, previousActionsData, to);
    }

    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        vaultLib.validateWithdrawal(s, withdrawalPriceData, previousActionsData);
    }

    function _calcWithdrawalAmountMSB(uint152 usdnShares) internal pure returns (uint128 sharesMSB_) {
        return vaultLib._calcWithdrawalAmountMSB(usdnShares);
    }

    function _calcWithdrawalAmountLSB(uint152 usdnShares) internal pure returns (uint24 sharesLSB_) {
        return vaultLib._calcWithdrawalAmountLSB(usdnShares);
    }

    function _checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) internal view {
        vaultLib._checkImbalanceLimitWithdrawal(s, withdrawalValue, totalExpo);
    }

    function _checkImbalanceLimitDeposit(uint256 depositValue) internal view {
        vaultLib._checkImbalanceLimitDeposit(s, depositValue);
    }

    function _vaultAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        return vaultLib._vaultAssetAvailable(s, currentPrice);
    }

    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) internal view returns (uint256 sdexToBurn_) {
        return vaultLib._calcSdexToBurn(s, usdnAmount, sdexBurnRatio);
    }

    function _convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        internal
        pure
        returns (PendingAction memory pendingAction_)
    {
        return vaultLib._convertWithdrawalPendingAction(action);
    }

    function _createInitialDeposit(uint128 amount, uint128 price) internal {
        _checkUninitialized(); // prevent using this function after initialization
        vaultLib._createInitialDeposit(s, amount, price);
    }

    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable initializer {
        vaultLib.initialize(s, depositAmount, longAmount, desiredLiqPrice, currentPriceData);
    }
}
