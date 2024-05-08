// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { IUsdnProtocolActions } from "src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import {
    Position,
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    LiquidationsEffects,
    PreviousActionsData,
    PositionId,
    TickData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";

abstract contract UsdnProtocolActionsEntry is UsdnProtocolBaseStorage, InitializableReentrancyGuard {
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolActions.initiateDeposit.selector, amount, currentPriceData, previousActionsData, to
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
            abi.encodeWithSelector(IUsdnProtocolActions.validateDeposit.selector, depositPriceData, previousActionsData)
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
                IUsdnProtocolActions.initiateWithdrawal.selector, usdnShares, currentPriceData, previousActionsData, to
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
                IUsdnProtocolActions.validateWithdrawal.selector, withdrawalPriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant returns (PositionId memory posId_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolActions.initiateOpenPosition.selector,
                amount,
                desiredLiqPrice,
                currentPriceData,
                previousActionsData,
                to
            )
        );
        require(success, "failed");
        posId_ = abi.decode(data, (PositionId));
    }

    function validateOpenPosition(bytes calldata openPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateOpenPosition.selector, openPriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolActions.initiateClosePosition.selector,
                posId,
                amountToClose,
                currentPriceData,
                previousActionsData,
                to
            )
        );
        require(success, "failed");
    }

    function validateClosePosition(bytes calldata closePriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateClosePosition.selector, closePriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 liquidatedPositions_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolActions.liquidate.selector, currentPriceData, iterations)
        );
        require(success, "failed");
        liquidatedPositions_ = abi.decode(data, (uint256));
    }

    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 validatedActions_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolActions.validateActionablePendingActions.selector, previousActionsData, maxValidations
            )
        );
        require(success, "failed");
        validatedActions_ = abi.decode(data, (uint256));
    }

    function _getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        public
        returns (PriceInfo memory price_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolActions._getOraclePrice.selector, action, timestamp, priceData)
        );
        require(success, "failed");
        price_ = abi.decode(data, (PriceInfo));
    }

    function _checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) public {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolActions._getOraclePrice.selector, openTotalExpoValue, openCollatValue)
        );
        require(success, "failed");
    }
}
