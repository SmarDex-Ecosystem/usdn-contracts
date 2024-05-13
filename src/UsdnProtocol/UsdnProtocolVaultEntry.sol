// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocolVault } from "src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { IUsdnProtocolVaultProxy } from "src/interfaces/UsdnProtocol/IUsdnProtocolVaultProxy.sol";
import { PendingAction, PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolCommonEntry } from "src/UsdnProtocol/UsdnProtocolCommonEntry.sol";

abstract contract UsdnProtocolVaultEntry is
    UsdnProtocolBaseStorage,
    UsdnProtocolCommonEntry,
    InitializableReentrancyGuard
{
    using SafeCast for int256;
    using SafeCast for uint256;

    function usdnPrice(uint128 currentPrice, uint128 timestamp) public returns (uint256 price_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSignature("usdnPrice(uint128,uint128)", currentPrice, timestamp)
        );
        require(success, "failed");
        price_ = abi.decode(data, (uint256));
    }

    function usdnPrice(uint128 currentPrice) external returns (uint256 price_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSignature("usdnPrice(uint128,uint128)", currentPrice));
        require(success, "failed");
        price_ = abi.decode(data, (uint256));
    }

    function getUserPendingAction(address user) external returns (PendingAction memory action_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultProxy.getUserPendingAction.selector, user)
        );
        require(success, "failed");
        action_ = abi.decode(data, (PendingAction));
    }

    function getActionablePendingActions(address currentUser)
        external
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVaultProxy.getActionablePendingActions.selector, currentUser)
        );
        require(success, "failed");
        (actions_, rawIndices_) = abi.decode(data, (PendingAction[], uint128[]));
    }

    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external returns (int256 expo_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultProxy.vaultTradingExpoWithFunding.selector, currentPrice, timestamp
            )
        );
        require(success, "failed");
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
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVault.previewWithdraw.selector, usdnShares, price, timestamp)
        );
        require(success, "failed");
        assetExpected_ = abi.decode(data, (uint256));
    }

    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        returns (int256 available_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultProxy.vaultAssetAvailableWithFunding.selector, currentPrice, timestamp
            )
        );
        require(success, "failed");
        available_ = abi.decode(data, (int256));
    }

    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultProxy.initiateDeposit.selector, amount, currentPriceData, previousActionsData, to
            )
        );
        require(success, "failed");
    }

    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultProxy.validateDeposit.selector, depositPriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function initiateWithdrawal(
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultProxy.initiateWithdrawal.selector,
                usdnShares,
                currentPriceData,
                previousActionsData,
                to
            )
        );
        require(success, "failed");
    }

    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVaultProxy.validateWithdrawal.selector, withdrawalPriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        public
        returns (uint256 toMint_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolVault._calcMintUsdn.selector, amount, vaultBalance, usdnTotalSupply, price
            )
        );
        require(success, "failed");
        toMint_ = abi.decode(data, (uint256));
    }
}
