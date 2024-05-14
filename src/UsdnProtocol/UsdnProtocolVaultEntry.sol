// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocolVaultImplementation } from "src/interfaces/UsdnProtocol/IUsdnProtocolVaultImplementation.sol";
import {
    PendingAction,
    PreviousActionsData,
    WithdrawalPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolCommonEntry } from "src/UsdnProtocol/UsdnProtocolCommonEntry.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

abstract contract UsdnProtocolVaultEntry is UsdnProtocolCommonEntry, InitializableReentrancyGuard {
    using SafeCast for int256;
    using SafeCast for uint256;

    function usdnPrice(uint128 currentPrice, uint128 timestamp) public returns (uint256 price_) {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSignature("usdnPrice(uint128,uint128)", currentPrice, timestamp)
        );
        if (!success) {
            revert(string(data));
        }
        price_ = abi.decode(data, (uint256));
    }

    function usdnPrice(uint128 currentPrice) external returns (uint256 price_) {
        (bool success, bytes memory data) =
            address(s._protocolVault).delegatecall(abi.encodeWithSignature("usdnPrice(uint128)", currentPrice));
        if (!success) {
            revert(string(data));
        }
        price_ = abi.decode(data, (uint256));
    }

    function getUserPendingAction(address user) external returns (PendingAction memory action_) {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation.getUserPendingAction.selector, user)
        );
        if (!success) {
            revert(string(data));
        }
        action_ = abi.decode(data, (PendingAction));
    }

    function getActionablePendingActions(address currentUser)
        external
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation.getActionablePendingActions.selector, currentUser)
        );
        if (!success) {
            revert(string(data));
        }
        (actions_, rawIndices_) = abi.decode(data, (PendingAction[], uint128[]));
    }

    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external returns (int256 expo_) {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation.vaultTradingExpoWithFunding.selector, currentPrice, timestamp
            )
        );
        if (!success) {
            revert(string(data));
        }
        expo_ = abi.decode(data, (int256));
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
        returns (uint256 assetExpected_)
    {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation.previewWithdraw.selector, usdnShares, price, timestamp
            )
        );
        if (!success) {
            revert(string(data));
        }
        assetExpected_ = abi.decode(data, (uint256));
    }

    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        returns (int256 available_)
    {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation.vaultAssetAvailableWithFunding.selector, currentPrice, timestamp
            )
        );
        if (!success) {
            revert(string(data));
        }
        available_ = abi.decode(data, (int256));
    }

    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation.initiateDeposit.selector,
                amount,
                currentPriceData,
                previousActionsData,
                to
            )
        );
        if (!success) {
            revert(string(data));
        }
    }

    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation.validateDeposit.selector, depositPriceData, previousActionsData
            )
        );
        if (!success) {
            revert(string(data));
        }
    }

    function initiateWithdrawal(
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation.initiateWithdrawal.selector,
                usdnShares,
                currentPriceData,
                previousActionsData,
                to
            )
        );
        if (!success) {
            revert(string(data));
        }
    }

    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation.validateWithdrawal.selector, withdrawalPriceData, previousActionsData
            )
        );
        if (!success) {
            revert(string(data));
        }
    }

    function _calcWithdrawalAmountMSB(uint152 usdnShares) internal returns (uint128 sharesMSB_) {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation._calcWithdrawalAmountMSB.selector, usdnShares)
        );
        if (!success) {
            revert(string(data));
        }
        sharesMSB_ = abi.decode(data, (uint128));
    }

    function _calcWithdrawalAmountLSB(uint152 usdnShares) internal returns (uint24 sharesLSB_) {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation._calcWithdrawalAmountLSB.selector, usdnShares)
        );
        if (!success) {
            revert(string(data));
        }
        sharesLSB_ = abi.decode(data, (uint24));
    }

    function _checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) internal {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultImplementation._checkImbalanceLimitWithdrawal.selector, withdrawalValue, totalExpo
            )
        );
        if (!success) {
            revert(string(data));
        }
    }

    function _checkImbalanceLimitDeposit(uint256 depositValue) internal {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation._checkImbalanceLimitDeposit.selector, depositValue)
        );
        if (!success) {
            revert(string(data));
        }
    }

    function _vaultAssetAvailable(uint128 currentPrice) internal returns (int256 available_) {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation._vaultAssetAvailable.selector, currentPrice)
        );
        if (!success) {
            revert(string(data));
        }
        available_ = abi.decode(data, (int256));
    }

    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) internal returns (uint256 sdexToBurn_) {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation._calcSdexToBurn.selector, usdnAmount, sdexBurnRatio)
        );
        if (!success) {
            revert(string(data));
        }
        sdexToBurn_ = abi.decode(data, (uint256));
    }

    function _convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        internal
        returns (PendingAction memory pendingAction_)
    {
        (bool success, bytes memory data) = address(s._protocolVault).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultImplementation._convertWithdrawalPendingAction.selector, action)
        );
        if (!success) {
            revert(string(data));
        }
        pendingAction_ = abi.decode(data, (PendingAction));
    }
}
