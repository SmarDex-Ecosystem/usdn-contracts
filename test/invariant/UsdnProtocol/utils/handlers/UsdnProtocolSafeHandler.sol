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

    function adminFunctionsTest(uint256 functionSeed, uint256 seed1, uint256 seed2, int256 seedInt) external {
        functionSeed %= 22;
        if (functionSeed == 0) {
            _setValidatorDeadlines(uint128(seed1), uint128(seed2));
        } else if (functionSeed == 1) {
            _setMinLeverage(seed1);
        } else if (functionSeed == 2) {
            _setMaxLeverage(seed1);
        } else if (functionSeed == 3) {
            _setLiquidationPenalty(seed1);
        } else if (functionSeed == 4) {
            _setEMAPeriod(seed1);
        } else if (functionSeed == 5) {
            _setFundingSF(seed1);
        } else if (functionSeed == 6) {
            _setProtocolFeeBps(seed1);
        } else if (functionSeed == 7) {
            _setPositionFeeBps(seed1);
        } else if (functionSeed == 8) {
            _setVaultFeeBps(seed1);
        } else if (functionSeed == 9) {
            _setRebalancerBonusBps(seed1);
        } else if (functionSeed == 10) {
            _setSdexBurnOnDepositRatio(seed1);
        } else if (functionSeed == 11) {
            _setSecurityDepositValue(seed1);
        } else if (functionSeed == 12) {
            _setExpoImbalanceLimits(seed1, seed2, seedInt);
        } else if (functionSeed == 13) {
            _setMinLongPosition(seed1);
        } else if (functionSeed == 14) {
            _setSafetyMarginBps(seed1);
        } else if (functionSeed == 15) {
            _setLiquidationIteration(seed1);
        } else if (functionSeed == 16) {
            _setFeeThreshold(seed1);
        } else if (functionSeed == 17) {
            _setTargetUsdnPrice(seed1);
        } else if (functionSeed == 18) {
            _setUsdnRebaseThreshold(seed1);
        } else if (functionSeed == 19) {
            _setUsdnRebaseInterval(seed1);
        } else if (functionSeed == 20) {
            _pauseTest();
        } else if (functionSeed == 21) {
            _unpauseTest();
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

    /* ----------------------------- Admin functions ---------------------------- */

    function _setValidatorDeadlines(uint256 seed1, uint256 seed2) internal {
        uint16 lowLatencyDelay = s._oracleMiddleware.getLowLatencyDelay();
        uint128 newLowLatencyValidatorDeadline =
            uint128(bound(seed1, Constants.MIN_VALIDATION_DEADLINE, lowLatencyDelay));
        uint128 newOnChainValidatorDeadline = uint128(bound(seed2, 0, Constants.MAX_VALIDATION_DEADLINE));

        // todo : admin
        vm.startPrank(msg.sender);
        this.setValidatorDeadlines(newLowLatencyValidatorDeadline, newOnChainValidatorDeadline);
        vm.stopPrank();
        console.log(
            "ADMIN: newLowLatencyValidatorDeadline",
            newLowLatencyValidatorDeadline,
            "newOnChainValidatorDeadline",
            newOnChainValidatorDeadline
        );
    }

    function _setMinLeverage(uint256 seed) public {
        uint256 newMinLeverage = bound(seed, 10 ** Constants.LEVERAGE_DECIMALS + 1, s._maxLeverage - 1);

        vm.startPrank(msg.sender);
        this.setMinLeverage(newMinLeverage);
        vm.stopPrank();
        console.log("ADMIN: newMinLeverage", newMinLeverage);
    }

    function _setMaxLeverage(uint256 seed) public {
        uint256 newMaxLeverage = bound(seed, s._minLeverage + 1, Constants.MAX_LEVERAGE);

        vm.startPrank(msg.sender);
        this.setMinLeverage(newMaxLeverage);
        vm.stopPrank();
        console.log("ADMIN: newMaxLeverage", newMaxLeverage);
    }

    function _setLiquidationPenalty(uint256 seed) public {
        uint24 newLiquidationPenalty = uint24(bound(seed, 0, Constants.MAX_LIQUIDATION_PENALTY));

        vm.startPrank(msg.sender);
        this.setLiquidationPenalty(newLiquidationPenalty);
        vm.stopPrank();
        console.log("ADMIN: newLiquidationPenalty", newLiquidationPenalty);
    }

    function _setEMAPeriod(uint256 seed) public {
        uint128 newEMAPeriod = uint128(bound(seed, 0, Constants.MAX_EMA_PERIOD));

        vm.startPrank(msg.sender);
        this.setEMAPeriod(newEMAPeriod);
        vm.stopPrank();
        console.log("ADMIN: newEMAPeriod", newEMAPeriod);
    }

    function _setFundingSF(uint256 seed) public {
        uint256 newFundingSF = bound(seed, 0, 10 ** Constants.FUNDING_SF_DECIMALS);

        vm.startPrank(msg.sender);
        this.setFundingSF(newFundingSF);
        vm.stopPrank();
        console.log("ADMIN: newFundingSF", newFundingSF);
    }

    function _setProtocolFeeBps(uint256 seed) public {
        // max = 10%
        uint16 newProtocolFeeBps = uint16(bound(seed, 0, 1000));

        vm.startPrank(msg.sender);
        this.setProtocolFeeBps(newProtocolFeeBps);
        vm.stopPrank();
        console.log("ADMIN: newProtocolFeeBps", newProtocolFeeBps);
    }

    function _setPositionFeeBps(uint256 seed) public {
        uint16 newPositionFee = uint16(bound(seed, 0, Constants.MAX_POSITION_FEE_BPS));

        vm.startPrank(msg.sender);
        this.setPositionFeeBps(newPositionFee);
        vm.stopPrank();
        console.log("ADMIN: newPositionFee", newPositionFee);
    }

    function _setVaultFeeBps(uint256 seed) public {
        uint16 newVaultFee = uint16(bound(seed, 0, Constants.MAX_VAULT_FEE_BPS));

        vm.startPrank(msg.sender);
        this.setVaultFeeBps(newVaultFee);
        vm.stopPrank();
        console.log("ADMIN: newVaultFee", newVaultFee);
    }

    function _setRebalancerBonusBps(uint256 seed) public {
        uint16 newBonus = uint16(bound(seed, 0, Constants.BPS_DIVISOR));

        vm.startPrank(msg.sender);
        this.setRebalancerBonusBps(newBonus);
        vm.stopPrank();
        console.log("ADMIN: newRebalancerBonus", newBonus);
    }

    function _setSdexBurnOnDepositRatio(uint256 seed) public {
        uint32 newRatio = uint32(bound(seed, 0, Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20));

        vm.startPrank(msg.sender);
        this.setSdexBurnOnDepositRatio(newRatio);
        vm.stopPrank();
        console.log("ADMIN: newSdexBurnOnDepositRatio", newRatio);
    }

    function _setSecurityDepositValue(uint256 seed) public {
        // max 2 ether
        uint64 securityDepositValue = uint64(bound(seed, 0, 2 ether));

        vm.startPrank(msg.sender);
        this.setSecurityDepositValue(securityDepositValue);
        vm.stopPrank();
        console.log("ADMIN: newSecurityDepositValue", securityDepositValue);
    }

    function _setExpoImbalanceLimits(uint256 seedParameter, uint256 seed, int256 seedInt) public {
        int256 openExpoImbalanceLimitBps = this.getOpenExpoImbalanceLimitBps();
        int256 depositExpoImbalanceLimitBps = this.getDepositExpoImbalanceLimitBps();
        int256 withdrawalExpoImbalanceLimitBps = this.getWithdrawalExpoImbalanceLimitBps();
        int256 closeExpoImbalanceLimitBps = this.getCloseExpoImbalanceLimitBps();
        int256 rebalancerCloseExpoImbalanceLimitBps = this.getRebalancerCloseExpoImbalanceLimitBps();
        int256 longImbalanceTargetBps = this.getLongImbalanceTargetBps();

        seedParameter %= 6;
        if (seedParameter == 0) {
            // change openExpoImbalanceLimitBps
            // min = 3% and max = 100%
            openExpoImbalanceLimitBps = int256(bound(seed, 300, Constants.BPS_DIVISOR));
            console.log("ADMIN: newOpenExpoImbalanceLimitBps", openExpoImbalanceLimitBps);
        } else if (seedParameter == 1) {
            // change depositExpoImbalanceLimitBps
            // min = 3% and max = 100%
            depositExpoImbalanceLimitBps = int256(bound(seed, 300, Constants.BPS_DIVISOR));
            console.log("ADMIN: newDepositExpoImbalanceLimitBps", depositExpoImbalanceLimitBps);
        } else if (seedParameter == 2) {
            // change withdrawalExpoImbalanceLimitBps
            // if != 0, min = openExpoImbalanceLimitBps and max = 100%
            if (withdrawalExpoImbalanceLimitBps != 0) {
                withdrawalExpoImbalanceLimitBps =
                    int256(bound(seed, uint256(openExpoImbalanceLimitBps), Constants.BPS_DIVISOR));
            }
            console.log("ADMIN: newWithdrawalExpoImbalanceLimitBps", withdrawalExpoImbalanceLimitBps);
        } else if (seedParameter == 3) {
            // change closeExpoImbalanceLimitBps
            // if != 0, min = depositExpoImbalanceLimitBps and max = 100%
            if (closeExpoImbalanceLimitBps != 0) {
                closeExpoImbalanceLimitBps =
                    int256(bound(seed, uint256(depositExpoImbalanceLimitBps), Constants.BPS_DIVISOR));
            }
            console.log("ADMIN: newCloseExpoImbalanceLimitBps", closeExpoImbalanceLimitBps);
        } else if (seedParameter == 4) {
            // change rebalancerCloseExpoImbalanceLimitBps
            // if != 0, min = 3% and max = closeExpoImbalanceLimitBps
            if (rebalancerCloseExpoImbalanceLimitBps != 0) {
                rebalancerCloseExpoImbalanceLimitBps = int256(bound(seed, 300, uint256(closeExpoImbalanceLimitBps)));
            }
            console.log("ADMIN: newRebalancerCloseExpoImbalanceLimitBps", rebalancerCloseExpoImbalanceLimitBps);
        } else if (seedParameter == 5) {
            // min = max(-50%,-withdrawalExpoImbalanceLimitBps) and max = closeExpoImbalanceLimitBps
            int256 min = -500 > -withdrawalExpoImbalanceLimitBps ? -500 : -withdrawalExpoImbalanceLimitBps;

            longImbalanceTargetBps = bound(seedInt, min, closeExpoImbalanceLimitBps);
            console.log("ADMIN: newLongImbalanceTargetBps", longImbalanceTargetBps);
        }

        vm.startPrank(msg.sender);
        this.setExpoImbalanceLimits(
            uint256(openExpoImbalanceLimitBps),
            uint256(depositExpoImbalanceLimitBps),
            uint256(withdrawalExpoImbalanceLimitBps),
            uint256(closeExpoImbalanceLimitBps),
            uint256(rebalancerCloseExpoImbalanceLimitBps),
            longImbalanceTargetBps
        );
        vm.stopPrank();
    }

    function _setMinLongPosition(uint256 seed) public {
        uint128 newMinLongPosition = uint128(bound(seed, 0, 2 * 10 ** s._assetDecimals));

        vm.startPrank(msg.sender);
        this.setMinLongPosition(newMinLongPosition);
        vm.stopPrank();
        console.log("ADMIN: newMinLongPosition", newMinLongPosition);
    }

    function _setSafetyMarginBps(uint256 seed) public {
        uint16 newSafetyMarginBps = uint16(bound(seed, 0, Constants.MAX_SAFETY_MARGIN_BPS));

        vm.startPrank(msg.sender);
        this.setSafetyMarginBps(newSafetyMarginBps);
        vm.stopPrank();
        console.log("ADMIN: newSafetyMarginBps", newSafetyMarginBps);
    }

    function _setLiquidationIteration(uint256 seed) public {
        uint16 newLiquidationIteration = uint16(bound(seed, 0, Constants.MAX_LIQUIDATION_ITERATION));

        vm.startPrank(msg.sender);
        this.setLiquidationIteration(newLiquidationIteration);
        vm.stopPrank();
        console.log("ADMIN: newLiquidationIteration", newLiquidationIteration);
    }

    function _setFeeThreshold(uint256 seed) public {
        uint16 newFeeThreshold = uint16(bound(seed, 0, type(uint16).max));

        vm.startPrank(msg.sender);
        this.setFeeThreshold(newFeeThreshold);
        vm.stopPrank();
        console.log("ADMIN: newFeeThreshold", newFeeThreshold);
    }

    function _setTargetUsdnPrice(uint256 seed) public {
        // min = 1$
        uint128 newTargetUsdnPrice = uint128(bound(seed, 10 ** s._priceFeedDecimals, s._usdnRebaseThreshold));

        vm.startPrank(msg.sender);
        this.setTargetUsdnPrice(newTargetUsdnPrice);
        vm.stopPrank();
        console.log("ADMIN: newTargetUsdnPrice", newTargetUsdnPrice);
    }

    function _setUsdnRebaseThreshold(uint256 seed) public {
        // max = 1.1$
        uint128 newUsdnRebaseThreshold = uint128(bound(seed, s._targetUsdnPrice, 11 * 10 ** (s._priceFeedDecimals - 1)));

        vm.startPrank(msg.sender);
        this.setUsdnRebaseThreshold(newUsdnRebaseThreshold);
        vm.stopPrank();
        console.log("ADMIN: newUsdnRebaseThreshold", newUsdnRebaseThreshold);
    }

    function _setUsdnRebaseInterval(uint256 seed) public {
        uint256 newUsdnRebaseInterval = bound(seed, 0, 365 days);

        vm.startPrank(msg.sender);
        this.setUsdnRebaseInterval(newUsdnRebaseInterval);
        vm.stopPrank();
        console.log("ADMIN: newUsdnRebaseInterval", newUsdnRebaseInterval);
    }

    function _pauseTest() public {
        vm.startPrank(msg.sender);
        this.pause();
        vm.stopPrank();
        console.log("ADMIN: paused");
    }

    function _unpauseTest() public {
        vm.startPrank(msg.sender);
        this.unpause();
        vm.stopPrank();
        console.log("ADMIN: unpaused");
    }
}
