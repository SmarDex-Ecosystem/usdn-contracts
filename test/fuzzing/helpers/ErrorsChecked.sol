// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdnErrors } from "../../../src/interfaces/Usdn/IUsdnErrors.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { SignedMath } from "../../../src/libraries/SignedMath.sol";
import { TickMath } from "../../../src/libraries/TickMath.sol";
import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";

contract ErrorsChecked is Test {
    /* -------------------------------------------------------------------------- */
    /*                              Common errors                                 */
    /* -------------------------------------------------------------------------- */
    bytes4[] public INITIATE_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector
    ];

    bytes4[] public INITIALIZABLE_ERRORS = [
        InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector,
        InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector
    ];

    /* -------------------------------------------------------------------------- */
    /*                           Functionnal errors                               */
    /* -------------------------------------------------------------------------- */
    bytes4[][] public INITIATE_DEPOSIT_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
            IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector,
            IUsdnProtocolErrors.UsdnProtocolDepositTooSmall.selector,
            IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector,
            IUsdnProtocolErrors.UsdnProtocolPendingAction.selector,
            FixedPointMathLib.FullMulDivFailed.selector,
            SafeTransferLib.TransferFromFailed.selector,
            SignedMath.SignedMathDivideByZero.selector
        ]
    ];
    bytes4[][] public INITIATE_OPEN_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
            IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall.selector,
            IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector,
            IUsdnErrors.UsdnInsufficientSharesBalance.selector
        ]
    ];
    bytes4[][] public INITIATE_WITHDRAWAL_ERRORS = [
        [
            SignedMath.SignedMathDivideByZero.selector,
            IUsdnErrors.UsdnInsufficientSharesBalance.selector,
            TickMath.TickMathInvalidPrice.selector
        ]
    ];

    bytes4[][] public INITIATE_CLOSE_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolUnauthorized.selector,
            IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector,
            IUsdnProtocolErrors.UsdnProtocolLiquidationPriceSafetyMargin.selector,
            FixedPointMathLib.FullMulDivFailed.selector
        ]
    ];

    bytes4[][] public VALIDATE_DEPOSIT_ERRORS = [[IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector]];

    bytes4[][] public VALIDATE_WITHDRAWAL_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
            IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector,
            IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector
        ]
    ];

    bytes4[][] public VALIDATE_CLOSE_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
            IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector
        ]
    ];

    bytes4[][] public VALIDATE_OPEN_ERRORS = [[IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector]];

    bytes4[][] public VALIDATE_PENDING_ACTIONS_ERRORS = [[IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed.selector]];

    bytes4[][] public INITIALIZE_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolMinInitAmount.selector,
            IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector,
            IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice.selector
        ]
    ];

    bytes4[][] public LIQUIDATE_ERRORS =
        [[TickMath.TickMathInvalidPrice.selector, SignedMath.SignedMathDivideByZero.selector]];

    constructor() {
        INITIATE_DEPOSIT_ERRORS.push(INITIATE_ERRORS);
        INITIATE_OPEN_ERRORS.push(INITIATE_ERRORS);
        INITIATE_WITHDRAWAL_ERRORS.push(INITIATE_ERRORS);

        INITIATE_DEPOSIT_ERRORS.push(INITIALIZABLE_ERRORS);
        INITIATE_OPEN_ERRORS.push(INITIALIZABLE_ERRORS);
        INITIATE_WITHDRAWAL_ERRORS.push(INITIALIZABLE_ERRORS);
        INITIATE_CLOSE_ERRORS.push(INITIALIZABLE_ERRORS);
        VALIDATE_DEPOSIT_ERRORS.push(INITIALIZABLE_ERRORS);
        VALIDATE_WITHDRAWAL_ERRORS.push(INITIALIZABLE_ERRORS);
        VALIDATE_CLOSE_ERRORS.push(INITIALIZABLE_ERRORS);
        VALIDATE_OPEN_ERRORS.push(INITIALIZABLE_ERRORS);
        VALIDATE_PENDING_ACTIONS_ERRORS.push(INITIALIZABLE_ERRORS);
        INITIALIZE_ERRORS.push(INITIALIZABLE_ERRORS);
        LIQUIDATE_ERRORS.push(INITIALIZABLE_ERRORS);
    }

    function _checkErrors(bytes memory err, bytes4[][] memory errorsArrays) internal virtual {
        bool expected = false;
        for (uint256 arrayIndex = 0; arrayIndex < errorsArrays.length; arrayIndex++) {
            for (uint256 errorIndex = 0; errorIndex < errorsArrays[arrayIndex].length; errorIndex++) {
                if (errorsArrays[arrayIndex][errorIndex] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
        }
        if (expected) {
            emit log_named_bytes("Expected error ", err);
            return;
        } else {
            emit log_named_bytes("DOS ", err);
            assert(false);
        }
    }
}
