// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IRebalancerErrors } from "../../../src/interfaces/Rebalancer/IRebalancerErrors.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";
import { PropertiesBase } from "./PropertiesBase.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

abstract contract Properties_ERR is PropertiesBase {
    function invariant_ERR(bytes memory returnData) internal {
        bytes4 returnedError;
        assembly {
            returnedError := mload(add(returnData, 0x20))
        }

        bytes4[] memory allowedErrors = new bytes4[](95);

        // Deposit errors [0-5]
        allowedErrors[0] = IUsdnProtocolErrors.UsdnProtocolEmptyVault.selector;
        allowedErrors[1] = IUsdnProtocolErrors.UsdnProtocolDepositTooSmall.selector;
        allowedErrors[2] = IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector;
        allowedErrors[3] = IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector;
        allowedErrors[4] = IUsdnProtocolErrors.UsdnProtocolAmountReceivedTooSmall.selector;
        allowedErrors[5] = IUsdnProtocolErrors.UsdnProtocolDeadlineExceeded.selector;

        // Withdrawal errors [6-11]
        allowedErrors[6] = IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector;
        allowedErrors[7] = IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector;
        allowedErrors[8] = IUsdnProtocolErrors.UsdnProtocolAmountToCloseHigherThanPositionAmount.selector;
        allowedErrors[9] = IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed.selector;
        allowedErrors[10] = IUsdnProtocolErrors.UsdnProtocolUnexpectedBalance.selector;
        allowedErrors[11] = IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector;

        // General action errors [12-18]
        allowedErrors[12] = IUsdnProtocolErrors.UsdnProtocolUnauthorized.selector;
        allowedErrors[13] = IUsdnProtocolErrors.UsdnProtocolPendingAction.selector;
        allowedErrors[14] = IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector;
        allowedErrors[15] = IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector;
        allowedErrors[16] = IUsdnProtocolErrors.UsdnProtocolTimestampTooOld.selector;
        allowedErrors[17] = IUsdnProtocolErrors.UsdnProtocolDeadlineExceeded.selector;
        allowedErrors[18] = IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector;

        // Open Position errors [19-25]
        allowedErrors[19] = IUsdnProtocolErrors.UsdnProtocolLeverageTooLow.selector;
        allowedErrors[20] = IUsdnProtocolErrors.UsdnProtocolLeverageTooHigh.selector;
        allowedErrors[21] = IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall.selector;
        allowedErrors[22] = IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice.selector;
        allowedErrors[23] = IUsdnProtocolErrors.UsdnProtocolLiquidationPriceSafetyMargin.selector;
        allowedErrors[24] = IUsdnProtocolErrors.UsdnProtocolSlippageMaxPriceExceeded.selector;
        allowedErrors[25] = IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector;

        // Close Position errors [26-29]
        allowedErrors[26] = IUsdnProtocolErrors.UsdnProtocolOutdatedTick.selector;
        allowedErrors[27] = IUsdnProtocolErrors.UsdnProtocolPositionNotValidated.selector;
        allowedErrors[28] = IUsdnProtocolErrors.UsdnProtocolAmountToCloseHigherThanPositionAmount.selector;
        allowedErrors[29] = IUsdnProtocolErrors.UsdnProtocolSlippageMinPriceExceeded.selector;

        // Liquidation errors [30-32]
        allowedErrors[30] = IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector;
        allowedErrors[31] = IUsdnProtocolErrors.UsdnProtocolZeroLongTradingExpo.selector;
        allowedErrors[32] = IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector;

        // Oracle/Price errors [33-34]
        allowedErrors[33] = IUsdnProtocolErrors.UsdnProtocolInsufficientOracleFee.selector;
        allowedErrors[34] = IUsdnProtocolErrors.UsdnProtocolPaymentCallbackFailed.selector;

        // Action validation errors [35-36]
        allowedErrors[35] = IUsdnProtocolErrors.UsdnProtocolInvalidPendingActionData.selector;
        allowedErrors[36] = IUsdnProtocolErrors.UsdnProtocolInvalidRebalancerTick.selector;

        // Protocol initialization & configuration errors [37-40]
        allowedErrors[37] = IUsdnProtocolErrors.UsdnProtocolMinInitAmount.selector;
        allowedErrors[38] = IUsdnProtocolErrors.UsdnProtocolInvalidUsdn.selector;
        allowedErrors[39] = IUsdnProtocolErrors.UsdnProtocolInvalidAssetDecimals.selector;
        allowedErrors[40] = IUsdnProtocolErrors.UsdnProtocolInvalidTokenDecimals.selector;

        // Parameter validation errors [41-44]
        allowedErrors[41] = IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage.selector;
        allowedErrors[42] = IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage.selector;
        allowedErrors[43] = IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPenalty.selector;
        allowedErrors[44] = IUsdnProtocolErrors.UsdnProtocolInvalidEMAPeriod.selector;

        // IERC20 Errors [45-50]
        allowedErrors[45] = IERC20Errors.ERC20InsufficientBalance.selector;
        allowedErrors[46] = IERC20Errors.ERC20InvalidSender.selector;
        allowedErrors[47] = IERC20Errors.ERC20InvalidReceiver.selector;
        allowedErrors[48] = IERC20Errors.ERC20InsufficientAllowance.selector;
        allowedErrors[49] = IERC20Errors.ERC20InvalidApprover.selector;
        allowedErrors[50] = IERC20Errors.ERC20InvalidSpender.selector;

        // Oracle Errors [51-64]
        allowedErrors[51] = IOracleMiddlewareErrors.OracleMiddlewareWrongPrice.selector;
        allowedErrors[52] = IOracleMiddlewareErrors.OracleMiddlewarePriceTooOld.selector;
        allowedErrors[53] = IOracleMiddlewareErrors.OracleMiddlewarePriceTooRecent.selector;
        allowedErrors[54] = IOracleMiddlewareErrors.OracleMiddlewarePythPositiveExponent.selector;
        allowedErrors[55] = IOracleMiddlewareErrors.OracleMiddlewareConfRatioTooHigh.selector;
        allowedErrors[56] = IOracleMiddlewareErrors.OracleMiddlewareIncorrectFee.selector;
        allowedErrors[57] = IOracleMiddlewareErrors.OracleMiddlewarePythFeeSafeguard.selector;
        allowedErrors[58] = IOracleMiddlewareErrors.OracleMiddlewareRedstoneSafeguard.selector;
        allowedErrors[59] = IOracleMiddlewareErrors.OracleMiddlewareTransferFailed.selector;
        allowedErrors[60] = IOracleMiddlewareErrors.OracleMiddlewareTransferToZeroAddress.selector;
        allowedErrors[61] = IOracleMiddlewareErrors.OracleMiddlewareInvalidRecentPriceDelay.selector;
        allowedErrors[62] = IOracleMiddlewareErrors.OracleMiddlewareInvalidPenaltyBps.selector;
        allowedErrors[63] = IOracleMiddlewareErrors.OracleMiddlewareInvalidRoundId.selector;
        allowedErrors[64] = IOracleMiddlewareErrors.OracleMiddlewareInvalidLowLatencyDelay.selector;

        // Rebalancer Errors [65-82]
        allowedErrors[65] = IRebalancerErrors.RebalancerUserPending.selector;
        allowedErrors[66] = IRebalancerErrors.RebalancerUserLiquidated.selector;
        allowedErrors[67] = IRebalancerErrors.RebalancerInvalidAddressTo.selector;
        allowedErrors[68] = IRebalancerErrors.RebalancerInvalidAmount.selector;
        allowedErrors[69] = IRebalancerErrors.RebalancerInsufficientAmount.selector;
        allowedErrors[70] = IRebalancerErrors.RebalancerInvalidMaxLeverage.selector;
        allowedErrors[71] = IRebalancerErrors.RebalancerInvalidMinAssetDeposit.selector;
        allowedErrors[72] = IRebalancerErrors.RebalancerInvalidTimeLimits.selector;
        allowedErrors[73] = IRebalancerErrors.RebalancerUnauthorized.selector;
        allowedErrors[74] = IRebalancerErrors.RebalancerDepositUnauthorized.selector;
        allowedErrors[75] = IRebalancerErrors.RebalancerActionNotValidated.selector;
        allowedErrors[76] = IRebalancerErrors.RebalancerNoPendingAction.selector;
        allowedErrors[77] = IRebalancerErrors.RebalancerValidateTooEarly.selector;
        allowedErrors[78] = IRebalancerErrors.RebalancerActionCooldown.selector;
        allowedErrors[79] = IRebalancerErrors.RebalancerWithdrawalUnauthorized.selector;
        allowedErrors[80] = IRebalancerErrors.RebalancerEtherRefundFailed.selector;
        allowedErrors[81] = IRebalancerErrors.RebalancerInvalidDelegationSignature.selector;
        allowedErrors[82] = IRebalancerErrors.RebalancerCloseLockedUntil.selector;

        // SafeTransferLib Errors [83-88]
        allowedErrors[83] = SafeTransferLib.ETHTransferFailed.selector;
        allowedErrors[84] = SafeTransferLib.TransferFromFailed.selector;
        allowedErrors[85] = SafeTransferLib.TransferFailed.selector;
        allowedErrors[86] = SafeTransferLib.ApproveFailed.selector;
        allowedErrors[87] = SafeTransferLib.Permit2Failed.selector;
        allowedErrors[88] = SafeTransferLib.Permit2AmountOverflow.selector;

        allowedErrors[89] = ReentrancyGuard.ReentrancyGuardReentrantCall.selector;

        allowedErrors[90] = InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector;
        allowedErrors[91] = InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector;
        allowedErrors[92] = InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector;

        //FUZZING ERRORS

        allowedErrors[93] = IUsdnProtocolErrors.Fuzzing_ExpectedBehavior.selector;

        // EVM errors returns nothing
        allowedErrors[94] = bytes4(abi.encode(""));

        fl.errAllow(returnedError, allowedErrors, ERR_01);
    }
}
