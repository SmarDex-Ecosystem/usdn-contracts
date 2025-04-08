// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

import { FuzzStorageVariables } from "../helper/FuzzStorageVariables.sol";
import { FuzzActors } from "./FuzzActors.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";

import { IBaseRebalancer } from "../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancer } from "../../../src/interfaces/Rebalancer/IRebalancer.sol";
import { IUsdnProtocolActions } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolCore } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolFallback } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolLong } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { IUsdnProtocolLong } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolVault } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";

/**
 * @notice Helper contract containing low-level protocol function wrappers for fuzzing
 * @dev Emits call-specific events and handles direct encoded calls to the USDN protocol and its modules
 */
contract FunctionCalls is FuzzStorageVariables, FuzzActors {
    event MinTickCall();
    event GetPositionValueCall(IUsdnProtocolLong.PositionId posId, uint128 price, uint128 timestamp);
    event GetEffectiveTickForPriceCall(uint128 price);
    event GetEffectiveTickForPriceExtendedCall(
        uint128 price, uint256 assetPrice, uint256 longTradingExpo, HugeUint.Uint512 accumulator, int24 tickSpacing
    );
    event GetTickLiquidationPenaltyCall(int24 tick);

    // Events for UsdnProtocolCore
    event InitializeCall(uint128 depositAmount, uint128 longAmount, uint128 desiredLiqPrice, bytes currentPriceData);
    event FundingCall(uint128 timestamp);
    event GetUserPendingActionCall(address user);
    event LongAssetAvailableWithFundingCall(uint128 currentPrice, uint128 timestamp);
    event LongTradingExpoWithFundingCall(uint128 currentPrice, uint128 timestamp);

    event ValidateDepositCall(address validator, bytes depositPriceData, Types.PreviousActionsData previousActionsData);
    event InitiateWithdrawalCall(
        uint152 usdnShares,
        uint256 amountOutMin,
        address to,
        address validator,
        uint256 deadline,
        bytes currentPriceData,
        Types.PreviousActionsData previousActionsData
    );
    event ValidateWithdrawalCall(
        address validator, bytes withdrawalPriceData, Types.PreviousActionsData previousActionsData
    );
    event GetActionablePendingActionsCall(address currentUser);
    event UsdnPriceCall(uint128 currentPrice, uint128 timestamp);
    event UsdnPriceSimpleCall(uint128 currentPrice);
    event VaultAssetAvailableWithFundingCall(uint128 currentPrice, uint128 timestamp);

    // Events for UsdnProtocolActions
    event InitiateOpenPositionCall(
        uint128 amount,
        uint128 desiredLiqPrice,
        uint128 userMaxPrice,
        uint256 userMaxLeverage,
        address to,
        address validator,
        uint256 deadline,
        bytes currentPriceData,
        IUsdnProtocolActions.PreviousActionsData previousActionsData
    );
    event ValidateOpenPositionCall(
        address validator, bytes openPriceData, IUsdnProtocolActions.PreviousActionsData previousActionsData
    );
    event InitiateClosePositionCall(
        IUsdnProtocolActions.PositionId posId,
        uint128 amountToClose,
        uint256 userMinPrice,
        address to,
        address validator,
        uint256 deadline,
        bytes currentPriceData,
        IUsdnProtocolActions.PreviousActionsData previousActionsData
    );
    event InitiateClosePositionCallInRebalancer(uint88 amount, address to, uint256 userMinPrice);

    event ValidateClosePositionCall(
        address validator, bytes closePriceData, IUsdnProtocolActions.PreviousActionsData previousActionsData
    );
    event LiquidateCall(bytes currentPriceData);
    event ValidateActionablePendingActionsCall(
        IUsdnProtocolActions.PreviousActionsData previousActionsData, uint256 maxValidations
    );
    event TransferPositionOwnershipCall(IUsdnProtocolActions.PositionId posId, address newOwner);
    event TickHashCall(int24 tick, uint256 version);
    event GetLongPositionCall(IUsdnProtocolActions.PositionId posId);

    // Additional events for UsdnProtocolFallback
    event RemoveBlockedPendingActionNoCleanupCall(address validator, address to);
    event RemoveBlockedPendingActionByIndexCall(uint128 rawIndex, address to);
    event RemoveBlockedPendingActionNoCleanupByIndexCall(uint128 rawIndex, address to);
    event GetLeverageDecimalsCall();
    event GetFundingRateDecimalsCall();
    event GetRebalancerMinLeverageCall();
    event GetTokensDecimalsCall();
    event GetLiquidationMultiplierDecimalsCall();
    event GetFundingSfDecimalsCall();
    event GetSdexBurnOnDepositDivisorCall();
    event GetBpsDivisorCall();
    event GetMaxLiquidationIterationCall();
    event GetNoPositionTickCall();
    event GetDeadAddressCall();
    event GetMinUsdnSupplyCall();
    event GetMaxActionablePendingActionsCall();
    event GetMinLongTradingExpoBpsCall();
    event GetTickSpacingCall();
    event GetAssetCall();
    event GetSdexCall();
    event GetPriceFeedDecimalsCall();
    event GetAssetDecimalsCall();
    event GetUsdnCall();
    event GetUsdnMinDivisorCall();
    event GetOracleMiddlewareCall();
    event GetLiquidationRewardsManagerCall();
    event GetRebalancerCall();
    event GetMinLeverageCall();
    event GetMaxLeverageCall();
    event GetLowLatencyValidatorDeadlineCall();
    event GetOnChainValidatorDeadlineCall();
    event GetLiquidationPenaltyCall();
    event GetSafetyMarginBpsCall();
    event GetLiquidationIterationCall();
    event GetEmaPeriodCall();
    event GetFundingSfCall();
    event GetProtocolFeeBpsCall();
    event GetPositionFeeBpsCall();
    event GetVaultFeeBpsCall();
    event GetRebalancerBonusBpsCall();
    event GetSdexBurnOnDepositRatioCall();
    event GetSecurityDepositValueCall();
    event GetFeeThresholdCall();
    event GetFeeCollectorCall();
    event GetMiddlewareValidationDelayCall();
    event GetTargetUsdnPriceCall();
    event GetUsdnRebaseThresholdCall();
    event GetUsdnRebaseIntervalCall();
    event GetMinLongPositionCall();
    event GetLastFundingPerDayCall();
    event GetLastPriceCall();
    event GetLastUpdateTimestampCall();
    event GetPendingProtocolFeeCall();
    event GetBalanceVaultCall();
    event GetPendingBalanceVaultCall();
    event GetLastRebaseCheckCall();
    event GetEmaCall();
    event GetBalanceLongCall();
    event GetTotalExpoCall();
    event GetLiqMultiplierAccumulatorCall();
    event GetTickVersionCall(int24 tick);
    event GetTickDataCall(int24 tick);
    event GetCurrentLongPositionCall(int24 tick, uint256 index);
    event GetHighestPopulatedTickCall();
    event GetTotalLongPositionsCall();
    event GetDepositExpoImbalanceLimitBpsCall();
    event GetWithdrawalExpoImbalanceLimitBpsCall();
    event GetOpenExpoImbalanceLimitBpsCall();
    event GetCloseExpoImbalanceLimitBpsCall();
    event GetRebalancerCloseExpoImbalanceLimitBpsCall();
    event GetLongImbalanceTargetBpsCall();
    event GetFallbackAddressCall();
    event IsPausedCall();
    event SetOracleMiddlewareCall(address newOracleMiddleware);
    event SetLiquidationRewardsManagerCall(address newLiquidationRewardsManager);
    event SetRebalancerCall(address newRebalancer);
    event SetFeeCollectorCall(address newFeeCollector);
    event SetValidatorDeadlinesCall(uint128 newLowLatencyValidatorDeadline, uint128 newOnChainValidatorDeadline);
    event SetMinLeverageCall(uint256 newMinLeverage);
    event SetMaxLeverageCall(uint256 newMaxLeverage);
    event SetLiquidationPenaltyCall(uint24 newLiquidationPenalty);
    event SetEmaPeriodCall(uint128 newEmaPeriod);
    event SetFundingSfCall(uint256 newFundingSf);
    event SetProtocolFeeBpsCall(uint16 newProtocolFeeBps);
    event SetPositionFeeBpsCall(uint16 newPositionFee);
    event SetVaultFeeBpsCall(uint16 newVaultFee);
    event SetRebalancerBonusBpsCall(uint16 newBonus);
    event SetSdexBurnOnDepositRatioCall(uint32 newRatio);
    event SetSecurityDepositValueCall(uint64 securityDepositValue);
    event SetExpoImbalanceLimitsCall(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        uint256 newRebalancerCloseLimitBps,
        int256 newLongImbalanceTargetBps
    );
    event SetMinLongPositionCall(uint256 newMinLongPosition);
    event SetSafetyMarginBpsCall(uint256 newSafetyMarginBps);
    event SetLiquidationIterationCall(uint16 newLiquidationIteration);
    event SetFeeThresholdCall(uint256 newFeeThreshold);
    event SetTargetUsdnPriceCall(uint128 newPrice);
    event SetUsdnRebaseThresholdCall(uint128 newThreshold);
    event SetUsdnRebaseIntervalCall(uint256 newInterval);
    event PauseCall();
    event UnpauseCall();

    // UsdnProtocolLong function calls
    function _minTickCall() internal returns (bool success, bytes memory returnData) {
        emit MinTickCall();
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolLong.minTick.selector));
    }

    function _getPositionValueCall(IUsdnProtocolLong.PositionId memory posId, uint128 price, uint128 timestamp)
        internal
        returns (bool success, bytes memory returnData)
    {
        emit GetPositionValueCall(posId, price, timestamp);
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolLong.getPositionValue.selector, posId, price, timestamp)
        );
    }

    function _getEffectiveTickForPriceCall(uint128 price) internal returns (bool success, bytes memory returnData) {
        emit GetEffectiveTickForPriceCall(price);
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0x4c187765), price));
    }

    function _getTickLiquidationPenaltyCall(int24 tick) internal returns (bool success, bytes memory returnData) {
        emit GetTickLiquidationPenaltyCall(tick);
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolLong.getTickLiquidationPenalty.selector, tick)
        );
    }

    // UsdnProtocolCore function calls
    function _initializeCall(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes memory currentPriceData
    ) internal returns (bool success, bytes memory returnData) {
        emit InitializeCall(depositAmount, longAmount, desiredLiqPrice, currentPriceData);
        (success, returnData) = address(usdnProtocol).call{ value: msg.value }(
            abi.encodeWithSelector(
                IUsdnProtocolCore.initialize.selector, depositAmount, longAmount, desiredLiqPrice, currentPriceData
            )
        );
    }

    function _fundingCall(uint128 timestamp) internal returns (bool success, bytes memory returnData) {
        emit FundingCall(timestamp);
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolCore.funding.selector, timestamp));
    }

    // UsdnProtocolVault function calls
    function _initiateDepositCall(
        uint128 amount,
        uint256 sharesOutMin,
        address to,
        address payable validator,
        uint256 deadline,
        bytes memory currentPriceData,
        Types.PreviousActionsData memory previousActionsData,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        vm.prank(currentActor);
        (success, returnData) = address(usdnProtocol).call{ value: txValue }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.initiateDeposit.selector,
                amount,
                sharesOutMin,
                to,
                validator,
                deadline,
                currentPriceData,
                previousActionsData
            )
        );
    }

    function _validateDepositCall(
        address payable validator,
        bytes memory depositPriceData,
        Types.PreviousActionsData memory previousActionsData
    ) internal returns (bool success, bytes memory returnData) {
        emit ValidateDepositCall(validator, depositPriceData, previousActionsData);
        vm.prank(currentActor);
        (success, returnData) = address(usdnProtocol).call{ value: msg.value }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateDeposit.selector, validator, depositPriceData, previousActionsData
            )
        );
    }

    function _initiateWithdrawalCall(
        uint152 usdnShares,
        uint256 amountOutMin,
        address to,
        address payable validator,
        uint256 deadline,
        bytes memory currentPriceData,
        Types.PreviousActionsData memory previousActionsData,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        emit InitiateWithdrawalCall(
            usdnShares, amountOutMin, to, validator, deadline, currentPriceData, previousActionsData
        );
        vm.prank(currentActor);
        (success, returnData) = address(usdnProtocol).call{ value: txValue }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.initiateWithdrawal.selector,
                usdnShares,
                amountOutMin,
                to,
                validator,
                deadline,
                currentPriceData,
                previousActionsData
            )
        );
    }

    function _validateWithdrawalCall(
        address payable validator,
        bytes memory withdrawalPriceData,
        Types.PreviousActionsData memory previousActionsData
    ) internal returns (bool success, bytes memory returnData) {
        emit ValidateWithdrawalCall(validator, withdrawalPriceData, previousActionsData);
        vm.prank(currentActor);
        (success, returnData) = address(usdnProtocol).call{ value: msg.value }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateWithdrawal.selector, validator, withdrawalPriceData, previousActionsData
            )
        );
    }

    function _usdnPriceCall(uint128 currentPrice, uint128 timestamp)
        internal
        returns (bool success, bytes memory returnData)
    {
        emit UsdnPriceCall(currentPrice, timestamp);
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0xa63563cf), currentPrice, timestamp));
    }

    function _usdnPriceSimpleCall(uint128 currentPrice) internal returns (bool success, bytes memory returnData) {
        emit UsdnPriceSimpleCall(currentPrice);
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0x7aeabd99), currentPrice));
    }

    function _vaultAssetAvailableWithFundingCall(uint128 currentPrice, uint128 timestamp)
        internal
        returns (bool success, bytes memory returnData)
    {
        emit VaultAssetAvailableWithFundingCall(currentPrice, timestamp);
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolVault.vaultAssetAvailableWithFunding.selector, currentPrice, timestamp)
        );
    }

    // UsdnProtocolActions function calls
    function _initiateOpenPositionCall(
        uint128 amount,
        uint128 desiredLiqPrice,
        uint128 userMaxPrice,
        uint256 userMaxLeverage,
        address to,
        address payable validator,
        uint256 deadline,
        bytes memory currentPriceData,
        IUsdnProtocolActions.PreviousActionsData memory previousActionsData,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        emit InitiateOpenPositionCall(
            amount,
            desiredLiqPrice,
            userMaxPrice,
            userMaxLeverage,
            to,
            validator,
            deadline,
            currentPriceData,
            previousActionsData
        );
        vm.prank(currentActor);
        (success, returnData) = address(usdnProtocol).call{ value: txValue }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.initiateOpenPosition.selector,
                amount,
                desiredLiqPrice,
                userMaxPrice,
                userMaxLeverage,
                to,
                validator,
                deadline,
                currentPriceData,
                previousActionsData
            )
        );
    }

    function _initiateClosePositionCall(
        IUsdnProtocolActions.PositionId memory posId,
        uint128 amountToClose,
        uint256 userMinPrice,
        address to,
        address validator,
        uint256 deadline,
        bytes memory currentPriceData,
        IUsdnProtocolActions.PreviousActionsData memory previousActionsData,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        emit InitiateClosePositionCall(
            posId, amountToClose, userMinPrice, to, validator, deadline, currentPriceData, previousActionsData
        );
        vm.prank(currentActor);

        (success, returnData) = address(usdnProtocol).call{ value: txValue }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.initiateClosePosition.selector,
                posId,
                amountToClose,
                userMinPrice,
                to,
                validator,
                deadline,
                currentPriceData,
                previousActionsData
            )
        );
    }

    function _validateOpenPositionCall(
        address payable validator,
        bytes memory openPriceData,
        IUsdnProtocolActions.PreviousActionsData memory previousActionsData,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        emit ValidateOpenPositionCall(validator, openPriceData, previousActionsData);
        vm.prank(currentActor);

        (success, returnData) = address(usdnProtocol).call{ value: txValue }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateOpenPosition.selector, validator, openPriceData, previousActionsData
            )
        );
    }

    function _validateClosePositionCall(
        address payable validator,
        bytes memory closePriceData,
        IUsdnProtocolActions.PreviousActionsData memory previousActionsData,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        emit ValidateClosePositionCall(validator, closePriceData, previousActionsData);
        vm.prank(currentActor);

        (success, returnData) = address(usdnProtocol).call{ value: txValue }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateClosePosition.selector, validator, closePriceData, previousActionsData
            )
        );
    }

    function _liquidateCall(bytes memory currentPriceData) internal returns (bool success, bytes memory returnData) {
        emit LiquidateCall(currentPriceData);
        vm.prank(currentActor);
        (success, returnData) = address(usdnProtocol).call{ value: pythPrice }(
            abi.encodeWithSelector(IUsdnProtocolActions.liquidate.selector, currentPriceData)
        );
    }

    function _validateActionablePendingActionsCall(
        IUsdnProtocolActions.PreviousActionsData memory previousActionsData,
        uint256 maxValidations,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        emit ValidateActionablePendingActionsCall(previousActionsData, maxValidations);
        vm.prank(currentActor);
        (success, returnData) = address(usdnProtocol).call{ value: txValue }(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateActionablePendingActions.selector, previousActionsData, maxValidations
            )
        );
    }

    function _transferPositionOwnershipCall(IUsdnProtocolActions.PositionId memory posId, address newOwner)
        internal
        returns (bool success, bytes memory returnData)
    {
        emit TransferPositionOwnershipCall(posId, newOwner);
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolActions.transferPositionOwnership.selector, posId, newOwner)
        );
    }

    // UsdnProtocolFallback function calls
    function _getEffectivePriceForTickCall(int24 tick) internal returns (bool success, bytes memory returnData) {
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0x81ebaa8a), tick));
    }

    function _previewDepositCall(uint256 amount, uint128 price, uint128 timestamp)
        internal
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.previewDeposit.selector, amount, price, timestamp)
        );
    }

    function _previewWithdrawCall(uint256 usdnShares, uint128 price, uint128 timestamp)
        internal
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.previewWithdraw.selector, usdnShares, price, timestamp)
        );
    }

    function _refundSecurityDepositCall(address payable validator)
        internal
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.refundSecurityDeposit.selector, validator)
        );
    }

    function _removeBlockedPendingActionCall(address validator, address payable to)
        internal
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0xc58aaa96), validator, to));
    }

    // Additional functions for UsdnProtocolFallback
    function _removeBlockedPendingActionNoCleanupCall(address validator, address payable to)
        internal
        returns (bool success, bytes memory returnData)
    {
        emit RemoveBlockedPendingActionNoCleanupCall(validator, to);
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0xb82ee8b6), validator, to));
    }

    function _removeBlockedPendingActionByIndexCall(uint128 rawIndex, address payable to)
        internal
        returns (bool success, bytes memory returnData)
    {
        emit RemoveBlockedPendingActionByIndexCall(rawIndex, to);
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0xf980a965), rawIndex, to));
    }

    function _removeBlockedPendingActionNoCleanupByIndexCall(uint128 rawIndex, address payable to)
        internal
        returns (bool success, bytes memory returnData)
    {
        emit RemoveBlockedPendingActionNoCleanupByIndexCall(rawIndex, to);
        (success, returnData) = address(usdnProtocol).call(abi.encodeWithSelector(bytes4(0xa2dac055), rawIndex, to));
    }

    function _getTickSpacingCall() internal returns (bool success, bytes memory returnData) {
        emit GetTickSpacingCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getTickSpacing.selector));
    }

    function _getAssetCall() internal returns (bool success, bytes memory returnData) {
        emit GetAssetCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getAsset.selector));
    }

    function _getSdexCall() internal returns (bool success, bytes memory returnData) {
        emit GetSdexCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getSdex.selector));
    }

    function _getPriceFeedDecimalsCall() internal returns (bool success, bytes memory returnData) {
        emit GetPriceFeedDecimalsCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getPriceFeedDecimals.selector));
    }

    function _getAssetDecimalsCall() internal returns (bool success, bytes memory returnData) {
        emit GetAssetDecimalsCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getAssetDecimals.selector));
    }

    function _getUsdnCall() internal returns (bool success, bytes memory returnData) {
        emit GetUsdnCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getUsdn.selector));
    }

    function _getUsdnMinDivisorCall() internal returns (bool success, bytes memory returnData) {
        emit GetUsdnMinDivisorCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getUsdnMinDivisor.selector));
    }

    function _getOracleMiddlewareCall() internal returns (bool success, bytes memory returnData) {
        emit GetOracleMiddlewareCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getOracleMiddleware.selector));
    }

    function _getLiquidationRewardsManagerCall() internal returns (bool success, bytes memory returnData) {
        emit GetLiquidationRewardsManagerCall();
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.getLiquidationRewardsManager.selector)
        );
    }

    function _getRebalancerCall() internal returns (bool success, bytes memory returnData) {
        emit GetRebalancerCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getRebalancer.selector));
    }

    function _getMinLeverageCall() internal returns (bool success, bytes memory returnData) {
        emit GetMinLeverageCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getMinLeverage.selector));
    }

    function _getMaxLeverageCall() internal returns (bool success, bytes memory returnData) {
        emit GetMaxLeverageCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getMaxLeverage.selector));
    }

    function _getLowLatencyValidatorDeadlineCall() internal returns (bool success, bytes memory returnData) {
        emit GetLowLatencyValidatorDeadlineCall();
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.getLowLatencyValidatorDeadline.selector)
        );
    }

    function _getOnChainValidatorDeadlineCall() internal returns (bool success, bytes memory returnData) {
        emit GetOnChainValidatorDeadlineCall();
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.getOnChainValidatorDeadline.selector)
        );
    }

    function _getLiquidationPenaltyCall() internal returns (bool success, bytes memory returnData) {
        emit GetLiquidationPenaltyCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getLiquidationPenalty.selector));
    }

    function _getSafetyMarginBpsCall() internal returns (bool success, bytes memory returnData) {
        emit GetSafetyMarginBpsCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getSafetyMarginBps.selector));
    }

    function _getLiquidationIterationCall() internal returns (bool success, bytes memory returnData) {
        emit GetLiquidationIterationCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getLiquidationIteration.selector));
    }

    function _getEmaPeriodCall() internal returns (bool success, bytes memory returnData) {
        emit GetEmaPeriodCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getEMAPeriod.selector));
    }

    function _getFundingSfCall() internal returns (bool success, bytes memory returnData) {
        emit GetFundingSfCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getFundingSF.selector));
    }

    function _getProtocolFeeBpsCall() internal returns (bool success, bytes memory returnData) {
        emit GetProtocolFeeBpsCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getProtocolFeeBps.selector));
    }

    function _getPositionFeeBpsCall() internal returns (bool success, bytes memory returnData) {
        emit GetPositionFeeBpsCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getPositionFeeBps.selector));
    }

    function _getVaultFeeBpsCall() internal returns (bool success, bytes memory returnData) {
        emit GetVaultFeeBpsCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getVaultFeeBps.selector));
    }

    function _getRebalancerBonusBpsCall() internal returns (bool success, bytes memory returnData) {
        emit GetRebalancerBonusBpsCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getRebalancerBonusBps.selector));
    }

    function _getSdexBurnOnDepositRatioCall() internal returns (bool success, bytes memory returnData) {
        emit GetSdexBurnOnDepositRatioCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getSdexBurnOnDepositRatio.selector));
    }

    function _getSecurityDepositValueCall() internal returns (bool success, bytes memory returnData) {
        emit GetSecurityDepositValueCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getSecurityDepositValue.selector));
    }

    function _getFeeThresholdCall() internal returns (bool success, bytes memory returnData) {
        emit GetFeeThresholdCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getFeeThreshold.selector));
    }

    function _getFeeCollectorCall() internal returns (bool success, bytes memory returnData) {
        emit GetFeeCollectorCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getFeeCollector.selector));
    }

    function _getMiddlewareValidationDelayCall() internal returns (bool success, bytes memory returnData) {
        emit GetMiddlewareValidationDelayCall();
        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.getMiddlewareValidationDelay.selector)
        );
    }

    function _getTargetUsdnPriceCall() internal returns (bool success, bytes memory returnData) {
        emit GetTargetUsdnPriceCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getTargetUsdnPrice.selector));
    }

    function _getUsdnRebaseThresholdCall() internal returns (bool success, bytes memory returnData) {
        emit GetUsdnRebaseThresholdCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getUsdnRebaseThreshold.selector));
    }

    function _getLastFundingPerDayCall() internal returns (bool success, bytes memory returnData) {
        emit GetLastFundingPerDayCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getLastFundingPerDay.selector));
    }

    function _getBalanceVaultCall() internal returns (bool success, bytes memory returnData) {
        emit GetBalanceVaultCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getBalanceVault.selector));
    }

    function _getBalanceLongCall() internal returns (bool success, bytes memory returnData) {
        emit GetBalanceLongCall();
        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.getBalanceLong.selector));
    }

    function _initiateDepositAssetsCall(uint88 amount, address to)
        internal
        returns (bool success, bytes memory returnData)
    {
        vm.prank(currentActor);
        (success, returnData) =
            address(rebalancer).call(abi.encodeWithSelector(Rebalancer.initiateDepositAssets.selector, amount, to));
    }

    function _validateDepositAssetsCall() internal returns (bool success, bytes memory returnData) {
        vm.prank(currentActor);
        (success, returnData) =
            address(rebalancer).call(abi.encodeWithSelector(Rebalancer.validateDepositAssets.selector));
    }

    function _resetDepositAssetsCall() internal returns (bool success, bytes memory returnData) {
        vm.prank(currentActor);
        (success, returnData) = address(rebalancer).call(abi.encodeWithSelector(Rebalancer.resetDepositAssets.selector));
    }

    function _initiateWithdrawAssetsCall() internal returns (bool success, bytes memory returnData) {
        vm.prank(currentActor);
        (success, returnData) =
            address(rebalancer).call(abi.encodeWithSelector(Rebalancer.initiateWithdrawAssets.selector));
    }

    function _validateWithdrawAssetsCall(uint88 amount, address to)
        internal
        returns (bool success, bytes memory returnData)
    {
        vm.prank(currentActor);
        (success, returnData) =
            address(rebalancer).call(abi.encodeWithSelector(Rebalancer.validateWithdrawAssets.selector, amount, to));
    }

    function _initiateClosePositionCallInRebalancer(
        uint88 amount,
        address to,
        address payable validator,
        uint256 userMinPrice,
        uint256 deadline,
        bytes memory currentPriceData,
        Types.PreviousActionsData memory previousActionsData,
        bytes memory delegationData,
        uint256 txValue
    ) internal returns (bool success, bytes memory returnData) {
        emit InitiateClosePositionCallInRebalancer(amount, to, userMinPrice);
        vm.prank(currentActor);
        (success, returnData) = address(rebalancer).call{ value: txValue }(
            abi.encodeWithSelector(
                Rebalancer.initiateClosePosition.selector,
                amount,
                to,
                validator,
                userMinPrice,
                deadline,
                currentPriceData,
                previousActionsData,
                delegationData
            )
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              USDN Admin Calls                              */
    /* -------------------------------------------------------------------------- */

    function _setValidationDeadlines(uint256 lowLatencyDeadline, uint256 onChainDeadline)
        internal
        returns (bool success, bytes memory returnData)
    {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(
                IUsdnProtocolFallback.setValidatorDeadlines.selector, lowLatencyDeadline, onChainDeadline
            )
        );
    }

    function _setMinLeverage(uint256 minLeverage) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setMinLeverage.selector, minLeverage)
        );
    }

    function _setMaxLeverage(uint256 maxLeverage) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setMaxLeverage.selector, maxLeverage)
        );
    }

    function _setLiquidationPenalty(uint24 liquidationPenalty)
        internal
        returns (bool success, bytes memory returnData)
    {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setLiquidationPenalty.selector, liquidationPenalty)
        );
    }

    function _setEMAPeriod(uint128 emaPeriod) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.setEMAPeriod.selector, emaPeriod));
    }

    function _setFundingSF(uint256 fundingSF) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.setFundingSF.selector, fundingSF));
    }

    function _setProtocolFeeBps(uint16 protocolFeeBps) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setProtocolFeeBps.selector, protocolFeeBps)
        );
    }

    function _setPositionFeeBps(uint16 positionFee) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setPositionFeeBps.selector, positionFee)
        );
    }

    function _setVaultFeeBps(uint16 vaultFee) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.setVaultFeeBps.selector, vaultFee));
    }

    function _setSdexRewardsRatioBps(uint16 rewards) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setSdexRewardsRatioBps.selector, rewards)
        );
    }

    function _setRebalancerBonusBps(uint16 bonus) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setRebalancerBonusBps.selector, bonus)
        );
    }

    function _setSdexBurnOnDepositRatio(uint32 ratio) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setSdexBurnOnDepositRatio.selector, ratio)
        );
    }

    function _setSecurityDepositValue(uint64 securityDeposit)
        internal
        returns (bool success, bytes memory returnData)
    {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setSecurityDepositValue.selector, securityDeposit)
        );
    }

    function _setExpoImbalanceLimits(
        uint256 openLimit,
        uint256 depositLimit,
        uint256 withdrawalLimit,
        uint256 closeLimit,
        uint256 rebalancerCloseLimit,
        int256 longImbalanceTarget
    ) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(
                IUsdnProtocolFallback.setExpoImbalanceLimits.selector,
                openLimit,
                depositLimit,
                withdrawalLimit,
                closeLimit,
                rebalancerCloseLimit,
                longImbalanceTarget
            )
        );
    }

    function _setMinLongPosition(uint256 minLongPosition) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setMinLongPosition.selector, minLongPosition)
        );
    }

    function _setSafetyMarginBps(uint256 safetyMarginBps) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setSafetyMarginBps.selector, safetyMarginBps)
        );
    }

    function _setLiquidationIteration(uint16 liquidationIteration)
        internal
        returns (bool success, bytes memory returnData)
    {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setLiquidationIteration.selector, liquidationIteration)
        );
    }

    function _setFeeThreshold(uint256 feeThreshold) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setFeeThreshold.selector, feeThreshold)
        );
    }

    function _setTargetUsdnPrice(uint128 price) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolFallback.setTargetUsdnPrice.selector, price));
    }

    function _setUsdnRebaseThreshold(uint128 threshold) internal returns (bool success, bytes memory returnData) {
        vm.prank(ADMIN);

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolFallback.setUsdnRebaseThreshold.selector, threshold)
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Rebalancer                                 */
    /* -------------------------------------------------------------------------- */

    function _setPositionMaxLeverage(uint256 maxLeverage) internal returns (bool success, bytes memory returnData) {
        vm.prank(DEPLOYER);

        (success, returnData) =
            address(rebalancer).call(abi.encodeWithSelector(IRebalancer.setPositionMaxLeverage.selector, maxLeverage));
    }

    function _setMinAssetDeposit(uint256 minAssetDeposit) internal returns (bool success, bytes memory returnData) {
        vm.prank(DEPLOYER);

        (success, returnData) = address(rebalancer).call(
            abi.encodeWithSelector(IBaseRebalancer.setMinAssetDeposit.selector, minAssetDeposit)
        );
    }

    function _setTimeLimits(uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay)
        internal
        returns (bool success, bytes memory returnData)
    {
        vm.prank(DEPLOYER);

        (success, returnData) = address(rebalancer).call(
            abi.encodeWithSelector(
                IRebalancer.setTimeLimits.selector, validationDelay, validationDeadline, actionCooldown, closeDelay
            )
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidation Manger                             */
    /* -------------------------------------------------------------------------- */
}
