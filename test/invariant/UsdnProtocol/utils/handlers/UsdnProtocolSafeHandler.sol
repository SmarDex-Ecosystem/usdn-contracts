// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console } from "forge-std/console.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../../src/UsdnProtocol//libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "../../../../../src/UsdnProtocol/libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from
    "../../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { PriceInfo } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { Sdex } from "../../../../utils/Sdex.sol";
import { WstETH } from "../../../../utils/WstEth.sol";
import { UsdnProtocolHandler } from "./UsdnProtocolHandler.sol";

/**
 * @notice A handler for invariant testing of the USDN protocol which does not revert in normal operation
 * @dev Inputs are sanitized to prevent reverts. If a call is not possible, each function is a no-op
 */
contract UsdnProtocolSafeHandler is UsdnProtocolHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet _depositValidators;
    EnumerableSet.AddressSet _withdrawalValidators;
    EnumerableSet.AddressSet _openValidators;
    EnumerableSet.AddressSet _closeValidators;

    constructor(WstETH mockAsset, Sdex mockSdex) UsdnProtocolHandler(mockAsset, mockSdex) { }

    /* ------------------------ Protocol actions helpers ------------------------ */

    function initiateDepositTest(uint128 amount, address to, address payable validator) external {
        if (_maxDeposit() < _minDeposit()) {
            return;
        }
        validator = boundAddress(validator);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.None) {
            return;
        }
        _depositValidators.add(validator);
        amount = uint128(_bound(amount, _minDeposit(), _maxDeposit()));
        _mockAsset.mintAndApprove(msg.sender, amount, address(this), amount);
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 sdexToBurn;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            (, sdexToBurn) = this.previewDeposit(amount, uint128(price.neutralPrice), uint128(price.timestamp));
        } else {
            (, sdexToBurn) = this.previewDeposit(amount, uint128(price.neutralPrice), uint128(block.timestamp));
        }
        sdexToBurn = sdexToBurn * 15 / 10; // margin
        _mockSdex.mintAndApprove(msg.sender, sdexToBurn, address(this), sdexToBurn);

        vm.startPrank(msg.sender);
        this.initiateDeposit{ value: s._securityDepositValue }(
            amount, 0, boundAddress(to), validator, block.timestamp, "", _getPreviousActionsData(address(0))
        );
        vm.stopPrank();
        console.log("deposit of %s assets to %s with validator %s", amount, to, validator);
    }

    function validateDepositTest(address payable validator) external {
        validator = _boundValidator(validator, _depositValidators);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.ValidateDeposit) {
            return;
        }
        if (block.timestamp < action.timestamp + s._oracleMiddleware.getValidationDelay()) {
            return;
        }
        _depositValidators.remove(validator);
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateDeposit);
        vm.startPrank(msg.sender);
        this.validateDeposit{ value: oracleFee }(validator, "", _getPreviousActionsData(validator));
        vm.stopPrank();
        emit log_named_address("validate deposit for", validator);
    }

    function initiateWithdrawalTest(uint152 shares, address to, address payable validator) external {
        uint152 maxWithdrawal = _maxWithdrawal(s._usdn.sharesOf(msg.sender));
        if (maxWithdrawal < 1) {
            return;
        }
        validator = boundAddress(validator);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.None) {
            return;
        }
        _withdrawalValidators.add(validator);
        shares = uint152(_bound(shares, 1, maxWithdrawal));

        vm.startPrank(msg.sender);
        s._usdn.approve(address(this), shares);
        this.initiateWithdrawal{ value: s._securityDepositValue }(
            shares, 0, boundAddress(to), validator, block.timestamp, "", _getPreviousActionsData(address(0))
        );
        vm.stopPrank();
        console.log("withdrawal of %s shares to %s with validator %s", shares, to, validator);
    }

    function validateWithdrawalTest(address payable validator) external {
        validator = _boundValidator(validator, _withdrawalValidators);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.ValidateWithdrawal) {
            return;
        }
        if (block.timestamp < action.timestamp + s._oracleMiddleware.getValidationDelay()) {
            return;
        }
        _withdrawalValidators.remove(validator);
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateWithdrawal);
        vm.startPrank(msg.sender);
        this.validateWithdrawal{ value: oracleFee }(validator, "", _getPreviousActionsData(validator));
        vm.stopPrank();
        emit log_named_address("validate withdrawal for", validator);
    }

    function initiateOpenPositionTest(uint128 amount, int24 tick, address to, address payable validator) external {
        // first set desired liq price to have a leverage between min and max
        tick = int24(bound(tick, _minLeverageTick(), _maxLeverageTick()));
        uint256 desiredLiqPrice = Utils.getEffectivePriceForTick(
            tick,
            s._lastPrice,
            Core.longTradingExpoWithFunding(s, s._lastPrice, uint128(block.timestamp)),
            s._liqMultiplierAccumulator
        );
        uint128 liqPriceWithoutPenalty = Utils.getEffectivePriceForTick(
            Utils.calcTickWithoutPenalty(tick, s._liquidationPenalty),
            s._lastPrice,
            Core.longTradingExpoWithFunding(s, s._lastPrice, uint128(block.timestamp)),
            s._liqMultiplierAccumulator
        );
        // then, calculate the maximum long amount to avoid excessive imbalance
        uint128 adjustedPrice = uint128(s._lastPrice + s._lastPrice * s._positionFeeBps / Constants.BPS_DIVISOR);
        uint128 maxAmount = _maxLongAmount(adjustedPrice, liqPriceWithoutPenalty);
        if (maxAmount < s._minLongPosition) {
            return;
        }
        amount = uint128(_bound(amount, s._minLongPosition, maxAmount));
        // validator checks
        validator = boundAddress(validator);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.None) {
            return;
        }
        _openValidators.add(validator);
        _mockAsset.mintAndApprove(msg.sender, amount, address(this), amount);
        vm.startPrank(msg.sender);
        this.initiateOpenPosition{ value: s._securityDepositValue }(
            amount,
            uint128(desiredLiqPrice),
            type(uint128).max,
            s._maxLeverage,
            boundAddress(to),
            validator,
            block.timestamp,
            "",
            _getPreviousActionsData(address(0))
        );
        vm.stopPrank();
        console.log("open long of %s assets to %s with validator %s", amount, to, validator);
    }

    function validateOpenPositionTest(address payable validator) external {
        validator = _boundValidator(validator, _openValidators);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.ValidateOpenPosition) {
            return;
        }
        if (block.timestamp < action.timestamp + s._oracleMiddleware.getValidationDelay()) {
            return;
        }
        _openValidators.remove(validator);
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateOpenPosition);
        vm.startPrank(msg.sender);
        this.validateOpenPosition{ value: oracleFee }(validator, "", _getPreviousActionsData(validator));
        vm.stopPrank();
        emit log_named_address("validate open long for", validator);
    }

    /* ------------------------ Invariant testing helpers ----------------------- */

    function boundAddress(address addr) public view returns (address payable) {
        assumeNotPrecompile(addr);
        assumeNotForgeAddress(addr);
        // there is a 50% chance of returning one of the senders, otherwise the input address unless it's a contract
        bool isContract = addr.code.length > 0;
        if (isContract || uint256(uint160(addr)) % 2 == 0) {
            address[] memory senders = senders();
            return payable(senders[uint256(uint160(addr) / 2) % senders.length]);
        } else {
            return payable(addr);
        }
    }

    /* --------------------------- Internal functions --------------------------- */

    function _boundValidator(address addr, EnumerableSet.AddressSet storage validators)
        internal
        view
        returns (address payable)
    {
        uint256 length = validators.length();
        if (length == 0) {
            return payable(addr);
        }
        uint256 pick = uint256(uint160(addr)) % length;
        return payable(validators.at(pick));
    }
}
