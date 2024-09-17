// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

import { ILiquidationRewardsManager } from "../../../src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "../../../src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IRebalancer } from "../../../src/interfaces/Rebalancer/IRebalancer.sol";
import { IRebalancerEvents } from "../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";

/**
 * @custom:feature The admin functions of the protocol
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolAdmin is UsdnProtocolBaseFixture, IRebalancerEvents {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call all admin functions from not admin wallet
     * @custom:given The initial usdnProtocol state
     * @custom:when Non-admin wallet triggers admin contract function
     * @custom:then Each function should revert with the same custom accessControl error
     */
    function test_RevertWhen_nonAdminWalletCallAdminFunctions() public {
        vm.expectRevert(customError("SET_EXTERNAL_ROLE"));
        protocol.setOracleMiddleware(IOracleMiddleware(address(1)));

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setMinLeverage(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setMaxLeverage(0);

        vm.expectRevert(customError("CRITICAL_FUNCTIONS_ROLE"));
        protocol.setValidatorDeadlines(0, 0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setLiquidationPenalty(0);

        vm.expectRevert(customError("SET_OPTIONS_ROLE"));
        protocol.setSafetyMarginBps(0);

        vm.expectRevert(customError("SET_OPTIONS_ROLE"));
        protocol.setLiquidationIteration(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setEMAPeriod(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setFundingSF(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setProtocolFeeBps(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setSdexBurnOnDepositRatio(0);

        vm.expectRevert(customError("SET_EXTERNAL_ROLE"));
        protocol.setFeeCollector(address(this));

        vm.expectRevert(customError("SET_OPTIONS_ROLE"));
        protocol.setFeeThreshold(0);

        vm.expectRevert(customError("SET_EXTERNAL_ROLE"));
        protocol.setLiquidationRewardsManager(ILiquidationRewardsManager(address(this)));

        vm.expectRevert(customError("SET_EXTERNAL_ROLE"));
        protocol.setRebalancer(IRebalancer(address(this)));

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setSecurityDepositValue(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setMinLongPosition(100 ether);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setPositionFeeBps(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setVaultFeeBps(0);

        vm.expectRevert(customError("SET_PROTOCOL_PARAMS_ROLE"));
        protocol.setRebalancerBonusBps(0);
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because zero
     */
    function test_RevertWhen_setOracleMiddlewareWithZero() public adminPrank {
        // zero address disallowed
        vm.expectRevert(UsdnProtocolInvalidMiddlewareAddress.selector);
        // set middleware
        protocol.setOracleMiddleware(IOracleMiddleware(address(0)));
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setOracleMiddleware() public adminPrank {
        // expected event
        vm.expectEmit();
        emit OracleMiddlewareUpdated(address(this));
        // set middleware
        protocol.setOracleMiddleware(IOracleMiddleware(address(this)));
        // assert new middleware equal randAddress
        assertEq(address(protocol.getOracleMiddleware()), address(this));
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because zero
     */
    function test_RevertWhen_setMinLeverageWithZero() public adminPrank {
        // minLeverage zero disallowed
        vm.expectRevert(UsdnProtocolInvalidMinLeverage.selector);
        // set minLeverage
        protocol.setMinLeverage(0);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setMinLeverageWithMax() public adminPrank {
        uint256 maxLeverage = protocol.getMaxLeverage();
        // minLeverage higher than max disallowed
        vm.expectRevert(UsdnProtocolInvalidMinLeverage.selector);
        // set minLeverage
        protocol.setMinLeverage(maxLeverage);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setMinLeverage() public adminPrank {
        // allowed value
        uint256 expectedNewValue = 10 ** protocol.LEVERAGE_DECIMALS() + 1;
        // expected event
        vm.expectEmit();
        emit MinLeverageUpdated(expectedNewValue);
        // assign new minLeverage value
        protocol.setMinLeverage(expectedNewValue);
        // check new value is equal to expected value
        assertEq(protocol.getMinLeverage(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because lower than min
     */
    function test_RevertWhen_setMaxLeverageWithMin() public adminPrank {
        uint256 minLeverage = protocol.getMinLeverage();
        // maxLeverage lower than min disallowed
        vm.expectRevert(UsdnProtocolInvalidMaxLeverage.selector);
        // set maxLeverage
        protocol.setMaxLeverage(minLeverage);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setMaxLeverageWithMax() public adminPrank {
        // cache limit
        uint256 aboveLimit = 100 * 10 ** protocol.LEVERAGE_DECIMALS() + 1;
        // maxLeverage greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidMaxLeverage.selector);
        // set maxLeverage
        protocol.setMaxLeverage(aboveLimit);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setMaxLeverage() public adminPrank {
        // cache the new maxLeverage value to assign
        uint256 expectedNewValue = protocol.getMinLeverage() + 1;
        // expected event
        vm.expectEmit();
        emit MaxLeverageUpdated(expectedNewValue);
        // assign new maxLeverage value
        protocol.setMaxLeverage(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getMaxLeverage(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setValidatorDeadlines" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because lower than min disallowed
     */
    function test_RevertWhen_setValidatorDeadlinesWithMin() public adminPrank {
        vm.expectRevert(UsdnProtocolInvalidValidatorDeadline.selector);
        protocol.setValidatorDeadlines(59, 59);
    }

    /**
     * @custom:scenario Call "setValidatorDeadlines" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setValidatorDeadlineWithMax() public adminPrank {
        vm.expectRevert(UsdnProtocolInvalidValidatorDeadline.selector);
        protocol.setValidatorDeadlines(60, 1 days + 1);

        vm.expectRevert(UsdnProtocolInvalidValidatorDeadline.selector);
        protocol.setValidatorDeadlines(20 minutes + 1, 0);
    }

    /**
     * @custom:scenario Call "setValidatorDeadlines" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setValidatorDeadlines() public adminPrank {
        uint128 expectedLowLatencyNewValue = 61;
        uint128 expectedOnChainNewValue = 0;
        // expected event
        vm.expectEmit();
        emit ValidatorDeadlinesUpdated(expectedLowLatencyNewValue, expectedOnChainNewValue);
        protocol.setValidatorDeadlines(expectedLowLatencyNewValue, expectedOnChainNewValue);
        assertEq(protocol.getLowLatencyValidatorDeadline(), expectedLowLatencyNewValue);
        assertEq(protocol.getOnChainValidatorDeadline(), expectedOnChainNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setLiquidationPenaltyMax() public adminPrank {
        // liquidationPenalty greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidLiquidationPenalty.selector);
        // set liquidationPenalty
        protocol.setLiquidationPenalty(1501);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setLiquidationPenalty() public adminPrank {
        // cache the new liquidationPenalty value to assign
        uint8 expectedNewValue = 0;
        // expected event
        vm.expectEmit();
        emit LiquidationPenaltyUpdated(expectedNewValue);
        // assign new liquidationPenalty value
        protocol.setLiquidationPenalty(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getLiquidationPenalty(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setSafetyMarginBps" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setSafetyMarginBpsWithMax() public adminPrank {
        // safetyMargin greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidSafetyMarginBps.selector);
        // set safetyMargin
        protocol.setSafetyMarginBps(2001);
    }

    /**
     * @custom:scenario Call "setSafetyMarginBps" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setSafetyMarginBps() public adminPrank {
        // cache the new safetyMargin value to assign
        uint256 expectedNewValue = 0;
        // expected event
        vm.expectEmit();
        emit SafetyMarginBpsUpdated(expectedNewValue);
        // assign new safetyMargin value
        protocol.setSafetyMarginBps(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getSafetyMarginBps(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationIteration" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setLiquidationIterationWithMax() public adminPrank {
        uint16 aboveMax = protocol.MAX_LIQUIDATION_ITERATION() + 1;
        // liquidationIteration greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidLiquidationIteration.selector);
        // set liquidationIteration
        protocol.setLiquidationIteration(aboveMax);
    }

    /**
     * @custom:scenario Call "setLiquidationIteration" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setLiquidationIteration() public adminPrank {
        // cache the new liquidationIteration value to assign
        uint16 expectedNewValue = 0;
        // expected event
        vm.expectEmit();
        emit LiquidationIterationUpdated(expectedNewValue);
        // assign new liquidationIteration value
        protocol.setLiquidationIteration(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getLiquidationIteration(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setEMAPeriodWithMax() public adminPrank {
        // EMAPeriod greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidEMAPeriod.selector);
        // set EMAPeriod
        protocol.setEMAPeriod(90 days + 1);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setEMAPeriod() public adminPrank {
        // cache the new EMAPeriod value to assign
        uint128 expectedNewValue = 1;
        // expected event
        vm.expectEmit();
        emit EMAPeriodUpdated(expectedNewValue);
        // assign new EMAPeriod value
        protocol.setEMAPeriod(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getEMAPeriod(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test__RevertWhen_setFundingSFWithMax() public adminPrank {
        // cached limit
        uint256 aboveLimit = 10 ** protocol.FUNDING_SF_DECIMALS() + 1;
        // fundingSF greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidFundingSF.selector);
        // set fundingSF
        protocol.setFundingSF(aboveLimit);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setFundingSF() public adminPrank {
        // cache the new fundingSF value to assign
        uint256 expectedNewValue = 1;
        // expected event
        vm.expectEmit();
        emit FundingSFUpdated(expectedNewValue);
        // assign new fundingSF value
        protocol.setFundingSF(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getFundingSF(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setProtocolFeeBps" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setFeeBpsWithMax() public adminPrank {
        // above max value
        uint16 aboveMax = uint16(protocol.BPS_DIVISOR()) + 1;
        // feeBps greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidProtocolFeeBps.selector);
        // set feeBps
        protocol.setProtocolFeeBps(aboveMax);
    }

    /**
     * @custom:scenario Call "setProtocolFeeBps" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setFeeBps() public adminPrank {
        // cache the new feeBps value to assign
        uint16 expectedNewValue;
        // expected event
        vm.expectEmit();
        emit FeeBpsUpdated(expectedNewValue);
        // assign new feeBps value
        protocol.setProtocolFeeBps(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getProtocolFeeBps(), expectedNewValue);
    }

    /**
     * @custom:scenario The contract owner calls "setSdexBurnOnDepositRatio"
     * @custom:given The initial usdnProtocol state
     * @custom:when The owner calls setSdexBurnOnDepositRatio with a value higher than the limit
     * @custom:then The call reverts
     */
    function test_RevertWhen_setSdexBurnOnDepositRatioWithMax() public adminPrank {
        uint32 aboveMax = uint32(protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR() / 20 + 1);

        vm.expectRevert(UsdnProtocolInvalidBurnSdexOnDepositRatio.selector);
        protocol.setSdexBurnOnDepositRatio(aboveMax);
    }

    /**
     * @custom:scenario The contract owner calls "setSdexBurnOnDepositRatio"
     * @custom:given The initial usdnProtocol state
     * @custom:when The owner calls setSdexBurnOnDepositRatio
     * @custom:then The value should be updated
     * @custom:and a BurnSdexOnDepositRatioUpdated event should be emitted
     */
    function test_setSdexBurnOnDepositRatio() public adminPrank {
        uint16 expectedNewValue = uint16(protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR()) / 20;

        vm.expectEmit();
        emit BurnSdexOnDepositRatioUpdated(expectedNewValue);
        protocol.setSdexBurnOnDepositRatio(expectedNewValue);

        assertEq(protocol.getSdexBurnOnDepositRatio(), expectedNewValue, "The value should have been updated");
    }

    /**
     * @custom:scenario Call "setFeeCollector" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because address zero
     */
    function test_RevertWhen_setFeeCollectorWithZero() public adminPrank {
        // feeCollector address zero disallowed
        vm.expectRevert(UsdnProtocolInvalidFeeCollector.selector);
        // set feeBps
        protocol.setFeeCollector(address(0));
    }

    /**
     * @custom:scenario Call "setFeeCollector" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setFeeCollector() public adminPrank {
        // cache the new feeCollector address to assign
        address expectedNewValue = address(this);
        // expected event
        vm.expectEmit();
        emit FeeCollectorUpdated(expectedNewValue);
        // assign new feeCollector address
        protocol.setFeeCollector(expectedNewValue);
        // check new address is equal to the expected value
        assertEq(protocol.getFeeCollector(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setFeeThreshold" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setFeeThreshold() public adminPrank {
        // cache the new feeThreshold value to assign
        uint256 expectedNewValue = type(uint256).max;
        // expected event
        vm.expectEmit();
        emit FeeThresholdUpdated(expectedNewValue);
        // assign new feeThreshold value
        protocol.setFeeThreshold(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getFeeThreshold(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationRewardsManager" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because zero
     */
    function test_RevertWhen_setLiquidationRewardsManagerWithZero() public adminPrank {
        // zero address disallowed
        vm.expectRevert(UsdnProtocolInvalidLiquidationRewardsManagerAddress.selector);
        // set liquidation reward manager
        protocol.setLiquidationRewardsManager(ILiquidationRewardsManager(address(0)));
    }

    /**
     * @custom:scenario Call "setLiquidationRewardsManager" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setLiquidationRewardsManager() public adminPrank {
        // expected new value
        ILiquidationRewardsManager expectedNewValue = ILiquidationRewardsManager(address(this));
        // expected event
        vm.expectEmit();
        emit LiquidationRewardsManagerUpdated(address(expectedNewValue));
        // set liquidation reward manager
        protocol.setLiquidationRewardsManager(expectedNewValue);
        // assert new liquidation reward manager equal expectedNewValue
        assertEq(address(protocol.getLiquidationRewardsManager()), address(expectedNewValue));
    }

    /**
     * @dev As tolerating the zero address is unusual, this test is relevant even though it doesn't increase the
     * coverage
     * @custom:scenario Call "setRebalancer" from admin with the zero address
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then GetRebalancer returns the zero address
     */
    function test_setRebalancerWithZeroAddress() public adminPrank {
        vm.expectEmit();
        emit RebalancerUpdated(address(0));
        protocol.setRebalancer(IRebalancer(address(0)));

        assertEq(address(protocol.getRebalancer()), address(address(0)));
    }

    /**
     * @custom:scenario Call "setRebalancer" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setRebalancer() public adminPrank {
        IRebalancer expectedNewValue = IRebalancer(address(this));

        vm.expectEmit();
        emit RebalancerUpdated(address(this));
        protocol.setRebalancer(expectedNewValue);

        assertEq(address(protocol.getRebalancer()), address(expectedNewValue));
    }

    /**
     * @custom:scenario Call "setSecurityDepositValue" from admin
     * @custom:given The initial usdnProtocol state
     * @custom:when Admin wallet triggers the function
     * @custom:then The value should be updated
     */
    function test_setSecurityDepositValue() public adminPrank {
        uint64 newValue = 1 ether;
        // expected event
        vm.expectEmit();
        emit SecurityDepositValueUpdated(newValue);
        // set security deposit
        protocol.setSecurityDepositValue(newValue);
        // assert that the new value is equal to the expected value
        assertEq(protocol.getSecurityDepositValue(), newValue);
    }

    /**
     * @custom:scenario Call "setSecurityDepositValue" from admin
     * @custom:given The initial usdnProtocol state
     * @custom:when Admin wallet call function with zero
     * @custom:then The security deposit value should be updated to zero
     */
    function test_setSecurityDepositValue_zero() public adminPrank {
        // set security deposit to 0
        protocol.setSecurityDepositValue(0);
        assertEq(protocol.getSecurityDepositValue(), 0);
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers the function with a value above an int256
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_setExpoImbalanceLimitsMax() public adminPrank {
        uint256 aboveSignedMax = uint256(type(int256).max) + 1;
        bytes memory safecastError =
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintToInt.selector, aboveSignedMax);

        vm.expectRevert(safecastError);
        // set open expo  imbalance limit above max int
        protocol.setExpoImbalanceLimits(aboveSignedMax, 0, 0, 0, 0, 0);

        vm.expectRevert(safecastError);
        // set deposit expo imbalance limit above max int
        protocol.setExpoImbalanceLimits(0, aboveSignedMax, 0, 0, 0, 0);

        vm.expectRevert(safecastError);
        // set withdrawal expo imbalance limit above max int
        protocol.setExpoImbalanceLimits(0, 0, aboveSignedMax, 0, 0, 0);

        vm.expectRevert(safecastError);
        // set close expo imbalance limit above max int
        protocol.setExpoImbalanceLimits(0, 0, 0, aboveSignedMax, 0, 0);
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setExpoImbalanceLimits() public adminPrank {
        // limit basis point to assign
        uint256 expectedNewLimitBps = 0;
        // signed limit basis point
        int256 expectedSignedLimitBps = int256(expectedNewLimitBps);
        int256 expectedLongImbalanceTarget = expectedSignedLimitBps;

        // expected event
        vm.expectEmit();
        emit ImbalanceLimitsUpdated(
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedLongImbalanceTarget
        );

        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedNewLimitBps,
            expectedLongImbalanceTarget
        );

        // assert values are updated
        assertEq(protocol.getDepositExpoImbalanceLimitBps(), expectedSignedLimitBps, "open limit");
        assertEq(protocol.getWithdrawalExpoImbalanceLimitBps(), expectedSignedLimitBps, "deposit limit");
        assertEq(protocol.getOpenExpoImbalanceLimitBps(), expectedSignedLimitBps, "withdrawal limit");
        assertEq(protocol.getCloseExpoImbalanceLimitBps(), expectedSignedLimitBps, "close limit");
        assertEq(protocol.getRebalancerCloseExpoImbalanceLimitBps(), expectedSignedLimitBps, "close limit");
        assertEq(protocol.getLongImbalanceTargetBps(), expectedLongImbalanceTarget, "long imbalance target");
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function with below min values
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_setExpoImbalanceLimitsLow() public adminPrank {
        protocol.setExpoImbalanceLimits(2, 2, 0, 0, 0, 0);

        // open and deposit limits basis point
        int256 openLimitBps = protocol.getOpenExpoImbalanceLimitBps();
        int256 depositLimitBps = protocol.getDepositExpoImbalanceLimitBps();

        uint256 withdrawalLimitBpsBelowOpen = uint256(openLimitBps - 1);
        // expected revert
        vm.expectRevert(UsdnProtocolInvalidExpoImbalanceLimit.selector);
        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(
            uint256(openLimitBps), uint256(depositLimitBps), withdrawalLimitBpsBelowOpen, 0, 0, 0
        );

        uint256 closeLimitBpsBelowDeposit = uint256(depositLimitBps - 1);
        // expected revert
        vm.expectRevert(UsdnProtocolInvalidExpoImbalanceLimit.selector);
        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(
            uint256(openLimitBps),
            uint256(depositLimitBps),
            0,
            closeLimitBpsBelowDeposit,
            0,
            int256(closeLimitBpsBelowDeposit)
        );
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin with a target long imbalance too high
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when The long target imbalance is greater than the close imbalance
     * @custom:then The transaction should revert with an UsdnProtocolLongImbalanceTargetTooHigh error
     */
    function test_RevertWhen_setExpoImbalanceLimitsWithLongImbalanceTargetTooHigh() public adminPrank {
        int256 openLimitBps = protocol.getOpenExpoImbalanceLimitBps();
        int256 depositLimitBps = protocol.getDepositExpoImbalanceLimitBps();
        int256 closeLimitBps = protocol.getCloseExpoImbalanceLimitBps();
        int256 rebalancerCloseLimitBps = protocol.getRebalancerCloseExpoImbalanceLimitBps();
        int256 withdrawalLimitBps = protocol.getWithdrawalExpoImbalanceLimitBps();

        vm.expectRevert(UsdnProtocolInvalidLongImbalanceTarget.selector);
        // call with long imbalance target > closeLimitBps
        protocol.setExpoImbalanceLimits(
            uint256(openLimitBps),
            uint256(depositLimitBps),
            uint256(withdrawalLimitBps),
            uint256(closeLimitBps),
            uint256(rebalancerCloseLimitBps),
            closeLimitBps + 1
        );
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin with a rebalancer close imbalance limit higher
     * than the close imbalance limit
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when The rebalancer close imbalance is greater than the close imbalance
     * @custom:then The transaction should revert with an UsdnProtocolInvalidExpoImbalanceLimit error
     */
    function test_RevertWhen_setExpoImbalanceLimitsWithRebalancerCloseImbalanceTooHigh() public adminPrank {
        int256 openLimitBps = protocol.getOpenExpoImbalanceLimitBps();
        int256 depositLimitBps = protocol.getDepositExpoImbalanceLimitBps();
        int256 closeLimitBps = protocol.getCloseExpoImbalanceLimitBps();
        int256 withdrawalLimitBps = protocol.getWithdrawalExpoImbalanceLimitBps();

        vm.expectRevert(UsdnProtocolInvalidExpoImbalanceLimit.selector);
        // call with rebalancer close imbalance limit > closeLimitBps
        protocol.setExpoImbalanceLimits(
            uint256(openLimitBps),
            uint256(depositLimitBps),
            uint256(withdrawalLimitBps),
            uint256(closeLimitBps),
            uint256(closeLimitBps + 1),
            closeLimitBps
        );
    }

    /**
     * @custom:scenario Call {setExpoImbalanceLimits} from admin with a target long imbalance lower than
     * the inverted withdrawal limit
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when The long target imbalance is lower than the withdrawal imbalance
     * @custom:then The transaction should revert with an UsdnProtocolInvalidLongImbalanceTarget error
     */
    function test_RevertWhen_setExpoImbalanceLimitsWithLongImbalanceTargetLowerThanWithdrawalLimit()
        public
        adminPrank
    {
        int256 openLimitBps = protocol.getOpenExpoImbalanceLimitBps();
        int256 depositLimitBps = protocol.getDepositExpoImbalanceLimitBps();
        int256 closeLimitBps = protocol.getCloseExpoImbalanceLimitBps();
        int256 rebalancerCloseLimitBps = protocol.getRebalancerCloseExpoImbalanceLimitBps();
        int256 withdrawalLimitBps = protocol.getWithdrawalExpoImbalanceLimitBps();

        vm.expectRevert(UsdnProtocolInvalidLongImbalanceTarget.selector);
        // call with long imbalance target < `withdrawalLimitBps` * -1
        protocol.setExpoImbalanceLimits(
            uint256(openLimitBps),
            uint256(depositLimitBps),
            uint256(withdrawalLimitBps),
            uint256(closeLimitBps),
            uint256(rebalancerCloseLimitBps),
            -withdrawalLimitBps - 1
        );
    }

    /**
     * @custom:scenario Call {setExpoImbalanceLimits} from admin with a target long imbalance too low
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when The long target imbalance is lower than `-5000` (-50%)
     * @custom:then The transaction should revert with an {UsdnProtocolInvalidLongImbalanceTarget} error
     */
    function test_RevertWhen_setExpoImbalanceLimitsWithLongImbalanceTargetTooLow() public adminPrank {
        int256 openLimitBps = protocol.getOpenExpoImbalanceLimitBps();
        int256 depositLimitBps = protocol.getDepositExpoImbalanceLimitBps();
        int256 closeLimitBps = protocol.getCloseExpoImbalanceLimitBps();
        int256 rebalancerCloseLimitBps = protocol.getRebalancerCloseExpoImbalanceLimitBps();
        int256 withdrawalLimitBps = 10_000;

        vm.expectRevert(UsdnProtocolInvalidLongImbalanceTarget.selector);
        protocol.setExpoImbalanceLimits(
            uint256(openLimitBps),
            uint256(depositLimitBps),
            uint256(withdrawalLimitBps),
            uint256(closeLimitBps),
            uint256(rebalancerCloseLimitBps),
            -5001
        );
    }

    /**
     * @custom:scenario Call "setMinLongPosition" from admin
     * @custom:given The initial usdnProtocol state
     * @custom:when Admin wallet triggers the function
     * @custom:then The value should be updated
     */
    function test_setMinLongPosition() public adminPrank {
        uint256 newValue = 1 ether;
        // expected event
        vm.expectEmit();
        emit MinLongPositionUpdated(newValue);
        // set minimum long position
        protocol.setMinLongPosition(newValue);
        // assert that the new value is equal to the expected value
        assertEq(protocol.getMinLongPosition(), newValue);
    }

    /**
     * @custom:scenario Call "setMinLongPosition" from admin that will call rebalancer minimum deposit update
     * @custom:given _minAssetDeposit is less than the new value
     * @custom:when Admin wallet triggers the function
     * @custom:then The values should be updated
     */
    function test_setMinLongPosition_rebalancerUpdate() public adminPrank {
        protocol.setRebalancer(rebalancer);

        uint256 newValue = 1 ether;
        assertLt(rebalancer.getMinAssetDeposit(), newValue);

        // expected events
        vm.expectEmit(address(protocol));
        emit MinLongPositionUpdated(newValue);
        vm.expectEmit(address(rebalancer));
        emit MinAssetDepositUpdated(newValue);

        // set minimum long position
        protocol.setMinLongPosition(newValue);
        // assert that the new values are equal to the expected values
        assertEq(protocol.getMinLongPosition(), newValue, "protocol value isn't updated");
        assertEq(rebalancer.getMinAssetDeposit(), newValue, "rebalancer value isn't updated");
    }

    /**
     * @custom:scenario Call `setPositionFeeBps` as admin
     * @custom:when The admin sets the position fee between 0 and 2000 bps
     * @custom:then The position fee should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setPositionFeeBps() public adminPrank {
        uint16 newValue = 2000;
        vm.expectEmit();
        emit PositionFeeUpdated(newValue);
        protocol.setPositionFeeBps(newValue);
        assertEq(protocol.getPositionFeeBps(), newValue, "max");
        protocol.setPositionFeeBps(0);
        assertEq(protocol.getPositionFeeBps(), 0, "zero");
    }

    /**
     * @custom:scenario Try to set a position fee higher than the max allowed
     * @custom:when The admin sets the position fee to 2001 bps
     * @custom:then The transaction should revert with the corresponding error
     */
    function test_RevertWhen_setPositionFeeTooHigh() public adminPrank {
        vm.expectRevert(UsdnProtocolInvalidPositionFee.selector);
        protocol.setPositionFeeBps(2001);
    }

    /**
     * @custom:scenario Call `setVaultFeeBps` as admin
     * @custom:when The admin sets the vault fee between 0 and 2000 bps
     * @custom:then The vault fee should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setVaultFeeBps() public adminPrank {
        uint16 newValue = 2000;
        vm.expectEmit();
        emit VaultFeeUpdated(newValue);
        protocol.setVaultFeeBps(newValue);
        assertEq(protocol.getVaultFeeBps(), newValue, "max");
        protocol.setVaultFeeBps(0);
        assertEq(protocol.getVaultFeeBps(), 0, "zero");
    }

    /**
     * @custom:scenario Try to set a vault fee higher than the max allowed
     * @custom:when The admin sets the vault fee to 2001 bps
     * @custom:then The transaction should revert with the corresponding error
     */
    function test_RevertWhen_setVaultFeeTooHigh() public adminPrank {
        vm.expectRevert(UsdnProtocolInvalidVaultFee.selector);
        protocol.setVaultFeeBps(2001);
    }

    /**
     * @custom:scenario Call `setRebalancerBonusBps` as admin
     * @custom:when The admin sets the bonus between 0 and 10000 bps
     * @custom:then The bonus should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setRebalancerBonusBps() public adminPrank {
        uint16 newValue = 10_000;
        vm.expectEmit();
        emit RebalancerBonusUpdated(newValue);
        protocol.setRebalancerBonusBps(newValue);
        assertEq(protocol.getRebalancerBonusBps(), newValue, "max");
        protocol.setRebalancerBonusBps(0);
        assertEq(protocol.getRebalancerBonusBps(), 0, "zero");
    }

    /**
     * @custom:scenario Try to set a rebalancer bonus higher than the max allowed
     * @custom:when The admin sets the bonus to 10001 bps
     * @custom:then The transaction should revert with the corresponding error
     */
    function test_RevertWhen_setRebalancerBonusTooHigh() public adminPrank {
        vm.expectRevert(UsdnProtocolInvalidRebalancerBonus.selector);
        protocol.setRebalancerBonusBps(10_001);
    }

    /**
     * @custom:scenario Call `setTargetUsdnPrice` as admin
     * @custom:when The admin sets the target price at `newPrice`
     * @custom:then The target price should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setTargetUsdnPrice() external adminPrank {
        uint128 newPrice = 2 ether;
        vm.expectEmit();
        emit TargetUsdnPriceUpdated(newPrice);
        protocol.setTargetUsdnPrice(newPrice);
        assertEq(protocol.getTargetUsdnPrice(), newPrice);
    }

    /**
     * @custom:scenario Call "setTargetUsdnPrice" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because higher than `_usdnRebaseThreshold`
     */
    function test_RevertWhen_setTargetUsdnPriceWithMax() external {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.flags.enableUsdnRebase = true;
        super._setUp(params);

        uint128 maxThreshold = protocol.getUsdnRebaseThreshold() + 1;
        vm.prank(ADMIN);
        vm.expectRevert(UsdnProtocolInvalidTargetUsdnPrice.selector);
        protocol.setTargetUsdnPrice(maxThreshold);
    }

    /**
     * @custom:scenario Call "setTargetUsdnPrice" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because lower than 10 ** _priceFeedDecimals
     */
    function test_RevertWhen_setTargetUsdnPriceWithMin() external adminPrank {
        uint128 minThreshold = uint128(10 ** protocol.getPriceFeedDecimals());
        vm.expectRevert(UsdnProtocolInvalidTargetUsdnPrice.selector);
        protocol.setTargetUsdnPrice(minThreshold - 1);
    }

    /**
     * @custom:scenario Call `setUsdnRebaseThreshold` as admin
     * @custom:when The admin sets the threshold at `newThreshold`
     * @custom:then The threshold should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setUsdnRebaseThreshold() external {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.flags.enableUsdnRebase = true;
        super._setUp(params);

        uint128 newThreshold = protocol.getTargetUsdnPrice() + 1;

        vm.expectEmit();
        emit UsdnRebaseThresholdUpdated(newThreshold);
        vm.prank(ADMIN);
        protocol.setUsdnRebaseThreshold(newThreshold);
        assertEq(protocol.getUsdnRebaseThreshold(), newThreshold);
    }

    /**
     * @custom:scenario Call "setUsdnRebaseThreshold" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because lower than `_targetUsdnPrice`
     */
    function test_RevertWhen_setUsdnRebaseThresholdWithMin() external adminPrank {
        uint128 minThreshold = protocol.getTargetUsdnPrice();
        vm.expectRevert(UsdnProtocolInvalidUsdnRebaseThreshold.selector);
        protocol.setUsdnRebaseThreshold(minThreshold - 1);
    }

    function customError(string memory role) internal view returns (bytes memory customError_) {
        bytes memory roleBytes = bytes(role);
        customError_ = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), keccak256(roleBytes)
        );
    }
}
