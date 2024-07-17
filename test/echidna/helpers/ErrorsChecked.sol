// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdnErrors } from "../../../src/interfaces/Usdn/IUsdnErrors.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { SignedMath } from "../../../src/libraries/SignedMath.sol";
import { TickMath } from "../../../src/libraries/TickMath.sol";

contract ErrorsChecked is Test {
    bytes4[] public INITIATE_DEPOSIT_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector,
        IUsdnProtocolErrors.UsdnProtocolDepositTooSmall.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector,
        IUsdnProtocolErrors.UsdnProtocolPendingAction.selector,
        FixedPointMathLib.FullMulDivFailed.selector,
        SafeTransferLib.TransferFromFailed.selector,
        SignedMath.SignedMathDivideByZero.selector
    ];
    bytes4[] public INITIATE_OPEN_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector,
        IUsdnErrors.UsdnInsufficientSharesBalance.selector
    ];
    bytes4[] public INITIATE_WITHDRAWAL_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        SignedMath.SignedMathDivideByZero.selector,
        IUsdnErrors.UsdnInsufficientSharesBalance.selector,
        TickMath.TickMathInvalidPrice.selector
    ];

    bytes4[] public VALIDATE_DEPOSIT_ERRORS = [IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector];

    bytes4[] public VALIDATE_WITHDRAWAL_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
        IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector
    ];

    bytes4[] public VALIDATE_OPEN_ERRORS = [IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector];

    function _checkErrors(bytes memory err, bytes4[] storage errors) internal {
        bool expected = false;
        for (uint256 i = 0; i < errors.length; i++) {
            if (errors[i] == bytes4(err)) {
                expected = true;
                break;
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
