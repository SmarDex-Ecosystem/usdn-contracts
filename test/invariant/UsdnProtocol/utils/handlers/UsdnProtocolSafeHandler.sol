// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Vm, console } from "forge-std/Test.sol";

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

    mapping(address => PositionId[]) _userPositions;

    struct InitiateClosePositionData {
        PositionId posId;
        Position pos;
        uint128 lastPrice;
        uint128 liqPriceWithoutPenalty;
        uint128 maxCloseAmount;
    }

    struct UpdateIds {
        PositionId[] oldIds;
        PositionId[] newIds;
    }

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
        amount = uint128(_bound(amount, _minDeposit(), _maxDeposit()));
        _mockAsset.mintAndApprove(msg.sender, amount, address(this), amount);
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 sdexToBurn;
        if (price.timestamp > s._lastUpdateTimestamp) {
            (, sdexToBurn) = this.previewDeposit(amount, uint128(price.neutralPrice), uint128(price.timestamp));
        } else {
            (, sdexToBurn) = this.previewDeposit(amount, uint128(price.neutralPrice), uint128(block.timestamp));
        }
        sdexToBurn = sdexToBurn * 15 / 10; // margin
        _mockSdex.mintAndApprove(msg.sender, sdexToBurn, address(this), sdexToBurn);

        vm.startPrank(msg.sender);
        vm.recordLogs();
        bool success = this.initiateDeposit{ value: s._securityDepositValue }(
            amount, 0, boundAddress(to), validator, block.timestamp, "", _getPreviousActionsData(address(0))
        );
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            console.log("deposit of %s assets to %s with validator %s", amount, to, validator);
            _depositValidators.add(validator);
        } else {
            console.log("deposit skipped due to pending liquidations");
        }
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
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateDeposit);
        vm.startPrank(msg.sender);
        vm.recordLogs();
        bool success = this.validateDeposit{ value: oracleFee }(validator, "", _getPreviousActionsData(validator));
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            emit log_named_address("validate deposit for", validator);
            _depositValidators.remove(validator);
        } else {
            console.log("deposit validation skipped due to pending liquidations");
        }
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
        shares = uint152(_bound(shares, 1, maxWithdrawal));

        vm.startPrank(msg.sender);
        s._usdn.approve(address(this), shares);
        vm.recordLogs();
        bool success = this.initiateWithdrawal{ value: s._securityDepositValue }(
            shares, 0, boundAddress(to), validator, block.timestamp, "", _getPreviousActionsData(address(0))
        );
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            console.log("withdrawal of %s shares to %s with validator %s", shares, to, validator);
            _withdrawalValidators.add(validator);
        } else {
            console.log("withdrawal skipped due to pending liquidations");
        }
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
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateWithdrawal);
        vm.startPrank(msg.sender);
        vm.recordLogs();
        bool success = this.validateWithdrawal{ value: oracleFee }(validator, "", _getPreviousActionsData(validator));
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            emit log_named_address("validate withdrawal for", validator);
            _withdrawalValidators.remove(validator);
        } else {
            console.log("withdrawal validation skipped due to pending liquidations");
        }
    }

    function initiateOpenPositionTest(uint128 amount, int24 tick, address to, address payable validator) external {
        // first set desired liq price to have a leverage between min and max
        tick = int24(_bound(tick, _minLeverageTick(), _maxLeverageTick()));
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
        to = boundAddress(to);
        _mockAsset.mintAndApprove(msg.sender, amount, address(this), amount);
        vm.startPrank(msg.sender);
        vm.recordLogs();
        (bool success, PositionId memory posId) = this.initiateOpenPosition{ value: s._securityDepositValue }(
            amount,
            uint128(desiredLiqPrice),
            type(uint128).max,
            s._maxLeverage,
            to,
            validator,
            block.timestamp,
            "",
            _getPreviousActionsData(address(0))
        );
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            console.log("open long of %s assets to %s with validator %s", amount, to, validator);
            _openValidators.add(validator);
            _userPositions[to].push(posId);
        } else {
            console.log("open long skipped due to pending liquidations");
        }
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
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateOpenPosition);
        vm.startPrank(msg.sender);
        vm.recordLogs();
        bool success = this.validateOpenPosition{ value: oracleFee }(validator, "", _getPreviousActionsData(validator));
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            emit log_named_address("validate open long for", validator);
            _openValidators.remove(validator);
            // TODO: check if the position ID changed and update the _userPositions mapping
        } else {
            console.log("open long validation skipped due to pending liquidations");
        }
    }

    function initiateClosePositionTest(uint128 amount, address to, address payable validator) external {
        // retrieve a position from the msg.sender
        PositionId[] storage positions = _userPositions[msg.sender];
        if (positions.length == 0) {
            return;
        }
        InitiateClosePositionData memory data;
        data.posId.tick = type(int24).min; // sentinel value if we can't find a valid pos
        uint24 penalty;
        for (uint256 i; i < positions.length; i++) {
            (data.pos, penalty) = this.getLongPosition(positions[i]);
            if (!data.pos.validated) {
                // position must have been validated
                continue;
            }
            // found a suitable position, we record its ID
            data.posId = positions[i];
            break;
        }
        if (data.posId.tick == type(int24).min) {
            // no suitable position found
            return;
        }

        PriceInfo memory price = s._oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateClosePosition, ""
        );
        data.lastPrice = s._lastPrice;
        if (price.timestamp > s._lastUpdateTimestamp) {
            data.lastPrice = uint128(price.neutralPrice);
        }
        data.liqPriceWithoutPenalty = Utils.getEffectivePriceForTick(
            Utils.calcTickWithoutPenalty(data.posId.tick, penalty),
            data.lastPrice,
            Core.longTradingExpoWithFunding(s, data.lastPrice, uint128(block.timestamp)),
            s._liqMultiplierAccumulator
        );
        // max close amount to remain below imbalance limits
        data.maxCloseAmount = _maxCloseAmount(data.liqPriceWithoutPenalty, data.pos.totalExpo, data.pos.amount);
        // 50% chance of closing the position fully (if we're allowed to)
        // if we must close the position fully, then we do so
        if ((amount % 2 == 0 && data.pos.amount <= data.maxCloseAmount) || data.pos.amount - s._minLongPosition == 0) {
            amount = data.pos.amount;
        } else if (data.maxCloseAmount > data.pos.amount - s._minLongPosition) {
            // we can partial close only until we have at least minLongPosition left
            amount = uint128(_bound(amount, 1, data.pos.amount - s._minLongPosition));
        } else if (data.maxCloseAmount > 0) {
            // we can partial close up to maxCloseAmount
            amount = uint128(_bound(amount, 1, data.maxCloseAmount));
        } else {
            // can't close the position right now
            return;
        }
        validator = boundAddress(validator);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.None) {
            return;
        }
        to = boundAddress(to);
        vm.startPrank(msg.sender);
        vm.recordLogs();
        bool success = this.initiateClosePosition{ value: s._securityDepositValue }(
            data.posId, amount, 0, to, validator, block.timestamp, "", _getPreviousActionsData(address(0))
        );
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            _closeValidators.add(validator);
            if (data.pos.amount == amount) {
                console.log("close long of %s to %s with validator %s", msg.sender, to, validator);
                // remove from helper mapping
                PositionId[] storage userPositions = _userPositions[msg.sender];
                for (uint256 i = 0; i < userPositions.length; i++) {
                    if (userPositions[i].tick == data.posId.tick && userPositions[i].index == data.posId.index) {
                        if (i < userPositions.length - 1) {
                            // replace with last element
                            userPositions[i] = userPositions[userPositions.length - 1];
                        }
                        userPositions.pop();
                        break;
                    }
                }
            } else {
                console.log("partial close long of %s to %s with validator %s", msg.sender, to, validator);
            }
        } else {
            console.log("close long skipped due to pending liquidations");
        }
    }

    function validateClosePositionTest(address payable validator) external {
        validator = _boundValidator(validator, _closeValidators);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.ValidateClosePosition) {
            return;
        }
        if (block.timestamp < action.timestamp + s._oracleMiddleware.getValidationDelay()) {
            return;
        }
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateClosePosition);
        vm.startPrank(msg.sender);
        vm.recordLogs();
        bool success = this.validateClosePosition{ value: oracleFee }(validator, "", _getPreviousActionsData(validator));
        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());
        if (success) {
            emit log_named_address("validate close long for", validator);
            _closeValidators.remove(validator);
        } else {
            console.log("close long validation skipped due to pending liquidations");
        }
    }

    function validateActionablePendingActionsTest(uint256 maxValidations) external {
        (PendingAction[] memory prevActions, uint128[] memory rawIndices) = this.getActionablePendingActions(msg.sender);

        uint256 validationCost;
        if (prevActions.length == 0) {
            console.log("no actionable pending actions");
            return;
        } else {
            for (uint256 i = 0; i < prevActions.length; i++) {
                validationCost += s._oracleMiddleware.validationCost("", prevActions[i].action);
            }
        }

        bytes[] memory priceData = new bytes[](prevActions.length);
        PreviousActionsData memory previousData = PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });

        vm.startPrank(msg.sender);
        vm.recordLogs();

        uint256 validatedActions =
            this.validateActionablePendingActions{ value: validationCost }(previousData, maxValidations);

        vm.stopPrank();
        _updatePositionsMapping(vm.getRecordedLogs());

        console.log("validated ", validatedActions, " actions");
    }

    function liquidateTest() external {
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.Liquidation);

        vm.startPrank(msg.sender);
        LiqTickInfo[] memory liquidatedTicks = this.liquidate{ value: oracleFee }("");
        vm.stopPrank();

        if (liquidatedTicks.length > 0) {
            console.log("liquidated ", liquidatedTicks.length, " ticks");
        } else {
            console.log("no liquidations");
        }
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

    /// @dev during validateOpenPosition, a position ID can change, so we update the mapping according to the logs
    function _updatePositionsMapping(Vm.Log[] memory logs) internal {
        (PositionId[] memory oldIds, PositionId[] memory newIds) = _checkPosIdChanges(logs);
        for (uint256 i = 0; i < oldIds.length; i++) {
            (Position memory pos,) = this.getLongPosition(newIds[i]);
            // find the old position in the mapping and replace it
            PositionId[] storage userPositions = _userPositions[pos.user];
            for (uint256 j = 0; j < userPositions.length; j++) {
                if (userPositions[j].tick == oldIds[i].tick && userPositions[j].index == oldIds[i].index) {
                    // replace with the new ID
                    userPositions[j] = newIds[i];
                    break;
                }
            }
        }
    }
}
