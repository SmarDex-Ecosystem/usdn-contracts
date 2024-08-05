// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdnErrors } from "../../../src/interfaces/Usdn/IUsdnErrors.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { SignedMath } from "../../../src/libraries/SignedMath.sol";
import { TickMath } from "../../../src/libraries/TickMath.sol";
import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";

import { Setup } from "../Setup.sol";

contract ErrorsChecked is Setup {
    /* -------------------------------------------------------------------------- */
    /*                              Common errors                                 */
    /* -------------------------------------------------------------------------- */
    bytes4[] public INITIATE_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
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
            FixedPointMathLib.FullMulDivFailed.selector,
            InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
        ]
    ];

    bytes4[][] public VALIDATE_DEPOSIT_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
            InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
        ]
    ];

    bytes4[][] public VALIDATE_WITHDRAWAL_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
            IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector,
            IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector,
            InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
        ]
    ];

    bytes4[][] public VALIDATE_CLOSE_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
            IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector,
            InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
        ]
    ];

    bytes4[][] public VALIDATE_OPEN_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector,
            InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
        ]
    ];

    bytes4[][] public VALIDATE_PENDING_ACTIONS_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed.selector,
            InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
        ]
    ];

    bytes4[][] public INITIALIZE_ERRORS = [
        [
            IUsdnProtocolErrors.UsdnProtocolMinInitAmount.selector,
            IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector,
            IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice.selector
        ]
    ];

    constructor() {
        bytes4[] memory initiateErrors = INITIATE_ERRORS;
        INITIATE_DEPOSIT_ERRORS.push(initiateErrors);
        INITIATE_OPEN_ERRORS.push(initiateErrors);
        INITIATE_WITHDRAWAL_ERRORS.push(initiateErrors);
    }

    function _checkErrors(bytes memory err, bytes4[][] memory errorsArrays) internal {
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
            if (err != bytes4(InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector)) {
                // emit log_named_bytes("Uninitialized ", ); // todo get initialize position
                return;
            }
        } else {
            emit log_named_bytes("DOS ", err);
            assert(false);
        }
    }
}
