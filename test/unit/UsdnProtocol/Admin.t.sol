// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The admin functions of the protocol
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolAdmin is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.enableLimits = true;
        super._setUp(params);
    }

    /**
     * @custom:scenario Call all admin functions from non contract admin.
     * @custom:given The initial usdnProtocol state.
     * @custom:when Non admin wallet trigger admin contract function.
     * @custom:then Each functions should revert with the same custom Ownable error.
     */
    function test_RevertWhen_nonAdminWalletCallAdminFunctions() external {
        // Ownable contract custom error
        bytes memory customError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));

        vm.expectRevert(customError);
        protocol.setOracleMiddleware(IOracleMiddleware(address(1)));

        vm.expectRevert(customError);
        protocol.setMinLeverage(0);

        vm.expectRevert(customError);
        protocol.setMaxLeverage(0);

        vm.expectRevert(customError);
        protocol.setValidationDeadline(0);

        vm.expectRevert(customError);
        protocol.setLiquidationPenalty(0);

        vm.expectRevert(customError);
        protocol.setSafetyMarginBps(0);

        vm.expectRevert(customError);
        protocol.setLiquidationIteration(0);

        vm.expectRevert(customError);
        protocol.setEMAPeriod(0);

        vm.expectRevert(customError);
        protocol.setFundingSF(0);

        vm.expectRevert(customError);
        protocol.setProtocolFeeBps(0);

        vm.expectRevert(customError);
        protocol.setSdexBurnOnDepositRatio(0);

        vm.expectRevert(customError);
        protocol.setFeeCollector(address(this));

        vm.expectRevert(customError);
        protocol.setFeeThreshold(0);

        vm.expectRevert(customError);
        protocol.setLiquidationRewardsManager(ILiquidationRewardsManager(address(this)));

        vm.expectRevert(customError);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0);
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because zero.
     */
    function test_RevertWhen_setOracleMiddlewareWithZero() external adminPrank {
        // zero address disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidMiddlewareAddress.selector);
        // set middleware
        protocol.setOracleMiddleware(IOracleMiddleware(address(0)));
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setOracleMiddleware() external adminPrank {
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.OracleMiddlewareUpdated(address(this));
        // set middleware
        protocol.setOracleMiddleware(IOracleMiddleware(address(this)));
        // assert new middleware equal randAddress
        assertEq(address(protocol.getOracleMiddleware()), address(this));
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because zero.
     */
    function test_RevertWhen_setMinLeverageWithZero() external adminPrank {
        // minLeverage zero disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage.selector);
        // set minLeverage
        protocol.setMinLeverage(0);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setMinLeverageWithMax() external adminPrank {
        uint256 maxLeverage = protocol.getMaxLeverage();
        // minLeverage higher than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage.selector);
        // set minLeverage
        protocol.setMinLeverage(maxLeverage);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setMinLeverage() external adminPrank {
        // allowed value
        uint256 expectedNewValue = 10 ** protocol.LEVERAGE_DECIMALS() + 1;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.MinLeverageUpdated(expectedNewValue);
        // assign new minLeverage value
        protocol.setMinLeverage(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getMinLeverage(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because lower than min.
     */
    function test_RevertWhen_setMaxLeverageWithMin() external adminPrank {
        uint256 minLeverage = protocol.getMinLeverage();
        // maxLeverage lower than min disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage.selector);
        // set maxLeverage
        protocol.setMaxLeverage(minLeverage);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setMaxLeverageWithMax() external adminPrank {
        // cache limit
        uint256 aboveLimit = 100 * 10 ** protocol.LEVERAGE_DECIMALS() + 1;
        // maxLeverage greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage.selector);
        // set maxLeverage
        protocol.setMaxLeverage(aboveLimit);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setMaxLeverage() external adminPrank {
        // cache the new maxLeverage value to assign
        uint256 expectedNewValue = protocol.getMinLeverage() + 1;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.MaxLeverageUpdated(expectedNewValue);
        // assign new maxLeverage value
        protocol.setMaxLeverage(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getMaxLeverage(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because lower than min disallowed.
     */
    function test_RevertWhen_setValidationDeadlineWithMin() external adminPrank {
        // validationDeadline lower than min disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline.selector);
        // set validationDeadline
        protocol.setValidationDeadline(59);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setValidationDeadlineWithMax() external adminPrank {
        // validationDeadline greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidValidationDeadline.selector);
        // set validationDeadline
        protocol.setValidationDeadline(365 days + 1);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setValidationDeadline() external adminPrank {
        // cache the new validationDeadline value to assign
        uint256 expectedNewValue = 61;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.ValidationDeadlineUpdated(expectedNewValue);
        // assign new validationDeadline value
        protocol.setValidationDeadline(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getValidationDeadline(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setLiquidationPenaltyMax() external adminPrank {
        // liquidationPenalty greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPenalty.selector);
        // set liquidationPenalty
        protocol.setLiquidationPenalty(16);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setLiquidationPenalty() external adminPrank {
        // cache the new liquidationPenalty value to assign
        uint24 expectedNewValue = 0;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidationPenaltyUpdated(expectedNewValue);
        // assign new liquidationPenalty value
        protocol.setLiquidationPenalty(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getLiquidationPenalty(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setSafetyMarginBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setSafetyMarginBpsWithMax() external adminPrank {
        // safetyMargin greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidSafetyMarginBps.selector);
        // set safetyMargin
        protocol.setSafetyMarginBps(2001);
    }

    /**
     * @custom:scenario Call "setSafetyMarginBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setSafetyMarginBps() external adminPrank {
        // cache the new safetyMargin value to assign
        uint256 expectedNewValue = 0;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.SafetyMarginBpsUpdated(expectedNewValue);
        // assign new safetyMargin value
        protocol.setSafetyMarginBps(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getSafetyMarginBps(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationIteration" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setLiquidationIterationWithMax() external adminPrank {
        uint16 aboveMax = protocol.MAX_LIQUIDATION_ITERATION() + 1;
        // liquidationIteration greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationIteration.selector);
        // set liquidationIteration
        protocol.setLiquidationIteration(aboveMax);
    }

    /**
     * @custom:scenario Call "setLiquidationIteration" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setLiquidationIteration() external adminPrank {
        // cache the new liquidationIteration value to assign
        uint16 expectedNewValue = 0;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidationIterationUpdated(expectedNewValue);
        // assign new liquidationIteration value
        protocol.setLiquidationIteration(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getLiquidationIteration(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setEMAPeriodWithMax() external adminPrank {
        // EMAPeriod greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidEMAPeriod.selector);
        // set EMAPeriod
        protocol.setEMAPeriod(90 days + 1);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setEMAPeriod() external adminPrank {
        // cache the new EMAPeriod value to assign
        uint128 expectedNewValue = 1;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.EMAPeriodUpdated(expectedNewValue);
        // assign new EMAPeriod value
        protocol.setEMAPeriod(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getEMAPeriod(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test__RevertWhen_setFundingSFWithMax() external adminPrank {
        // cached limit
        uint256 aboveLimit = 10 ** protocol.FUNDING_SF_DECIMALS() + 1;
        // fundingSF greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidFundingSF.selector);
        // set fundingSF
        protocol.setFundingSF(aboveLimit);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setFundingSF() external adminPrank {
        // cache the new fundingSF value to assign
        uint256 expectedNewValue = 1;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.FundingSFUpdated(expectedNewValue);
        // assign new fundingSF value
        protocol.setFundingSF(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getFundingSF(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setProtocolFeeBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setFeeBpsWithMax() external adminPrank {
        // above max value
        uint16 aboveMax = uint16(protocol.BPS_DIVISOR()) + 1;
        // feeBps greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidProtocolFeeBps.selector);
        // set feeBps
        protocol.setProtocolFeeBps(aboveMax);
    }

    /**
     * @custom:scenario Call "setProtocolFeeBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setFeeBps() external adminPrank {
        // cache the new feeBps value to assign
        uint16 expectedNewValue;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.FeeBpsUpdated(expectedNewValue);
        // assign new feeBps value
        protocol.setProtocolFeeBps(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getProtocolFeeBps(), expectedNewValue);
    }

    /**
     * @custom:scenario The contract owner calls "setSdexBurnOnDepositRatio".
     * @custom:given The initial usdnProtocol state.
     * @custom:when Owner calls setSdexBurnOnDepositRatio with a value higher than the limit.
     * @custom:then The call reverts.
     */
    function test_RevertWhen_setSdexBurnOnDepositRatioWithMax() external adminPrank {
        uint32 aboveMax = uint32(protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR() / 20 + 1);

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidBurnSdexOnDepositRatio.selector);
        protocol.setSdexBurnOnDepositRatio(aboveMax);
    }

    /**
     * @custom:scenario The contract owner calls "setSdexBurnOnDepositRatio".
     * @custom:given The initial usdnProtocol state.
     * @custom:when Owner calls setSdexBurnOnDepositRatio.
     * @custom:then The value should be updated
     * @custom:and a BurnSdexOnDepositRatioUpdated event should be emitted.
     */
    function test_setSdexBurnOnDepositRatio() external adminPrank {
        uint16 expectedNewValue = uint16(protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR()) / 20;

        vm.expectEmit();
        emit IUsdnProtocolEvents.BurnSdexOnDepositRatioUpdated(expectedNewValue);
        protocol.setSdexBurnOnDepositRatio(expectedNewValue);

        assertEq(protocol.getSdexBurnOnDepositRatio(), expectedNewValue, "The value should have been updated");
    }

    /**
     * @custom:scenario Call "setFeeCollector" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because address zero.
     */
    function test_RevertWhen_setFeeCollectorWithZero() external adminPrank {
        // feeCollector address zero disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidFeeCollector.selector);
        // set feeBps
        protocol.setFeeCollector(address(0));
    }

    /**
     * @custom:scenario Call "setFeeCollector" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setFeeCollector() external adminPrank {
        // cache the new feeCollector address to assign
        address expectedNewValue = address(this);
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.FeeCollectorUpdated(expectedNewValue);
        // assign new feeCollector address
        protocol.setFeeCollector(expectedNewValue);
        // check new address is equal than expected
        assertEq(protocol.getFeeCollector(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setFeeThreshold" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setFeeThreshold() external adminPrank {
        // cache the new feeThreshold value to assign
        uint256 expectedNewValue = type(uint256).max;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.FeeThresholdUpdated(expectedNewValue);
        // assign new feeThreshold value
        protocol.setFeeThreshold(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getFeeThreshold(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationRewardsManager" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because zero.
     */
    function test_RevertWhen_setLiquidationRewardsManagerWithZero() external adminPrank {
        // zero address disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationRewardsManagerAddress.selector);
        // set liquidation reward manager
        protocol.setLiquidationRewardsManager(ILiquidationRewardsManager(address(0)));
    }

    /**
     * @custom:scenario Call "setLiquidationRewardsManager" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setLiquidationRewardsManager() external adminPrank {
        // expected new value
        ILiquidationRewardsManager expectedNewValue = ILiquidationRewardsManager(address(this));
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidationRewardsManagerUpdated(address(expectedNewValue));
        // set liquidation reward manager
        protocol.setLiquidationRewardsManager(expectedNewValue);
        // assert new liquidation reward manager equal expectedNewValue
        assertEq(address(protocol.getLiquidationRewardsManager()), address(expectedNewValue));
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function with above signed int max value.
     * @custom:then transaction should revert.
     */
    function test_RevertWhen_setExpoImbalanceLimitsMax() external adminPrank {
        uint256 aboveSignedMax = uint256(type(int256).max) + 1;
        bytes memory safecastError =
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintToInt.selector, aboveSignedMax);
        // expected revert
        vm.expectRevert(safecastError);
        // set open expo  imbalance limit above max int
        protocol.setExpoImbalanceLimits(aboveSignedMax, 0, 0, 0);

        // expected revert
        vm.expectRevert(safecastError);
        // set deposit expo imbalance limit above max int
        protocol.setExpoImbalanceLimits(0, aboveSignedMax, 0, 0);

        // expected revert
        vm.expectRevert(safecastError);
        // set withdrawal expo imbalance limit above max int
        protocol.setExpoImbalanceLimits(0, 0, aboveSignedMax, 0);

        // expected revert
        vm.expectRevert(safecastError);
        // set close expo imbalance limit above max int
        protocol.setExpoImbalanceLimits(0, 0, 0, aboveSignedMax);
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setExpoImbalanceLimits() external adminPrank {
        // limit basis point to assign
        uint256 expectedNewLimitBps = 0;
        // signed limit basis point
        int256 expectedSignedLimitBps = int256(expectedNewLimitBps);

        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.ImbalanceLimitsUpdated(
            expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps
        );

        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(
            expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps
        );

        // get signed limits basis point
        (int256 openLimitBps, int256 depositLimitBps, int256 withdrawalLimitBps, int256 closeLimitBps) =
            protocol.getExpoImbalanceLimits();

        // assert values are updated
        assertEq(openLimitBps, expectedSignedLimitBps);
        assertEq(depositLimitBps, expectedSignedLimitBps);
        assertEq(withdrawalLimitBps, expectedSignedLimitBps);
        assertEq(closeLimitBps, expectedSignedLimitBps);
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function with below min values.
     * @custom:then transaction should revert.
     */
    function test_RevertWhen_setExpoImbalanceLimitsLow() external adminPrank {
        // open and deposit limits basis point
        (int256 openLimitBps, int256 depositLimitBps,,) = protocol.getExpoImbalanceLimits();

        uint256 withdrawalLimitBpsBelowOpen = uint256(openLimitBps - 1);
        // expected revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidExpoImbalanceLimit.selector);
        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(uint256(openLimitBps), uint256(depositLimitBps), withdrawalLimitBpsBelowOpen, 0);

        uint256 closeLimitBpsBelowDeposit = uint256(depositLimitBps - 1);
        // expected revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidExpoImbalanceLimit.selector);
        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(uint256(openLimitBps), uint256(depositLimitBps), 0, closeLimitBpsBelowDeposit);
    }
}
