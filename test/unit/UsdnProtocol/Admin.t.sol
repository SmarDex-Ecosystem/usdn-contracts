// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IRebalancerEvents } from "src/interfaces/Rebalancer/IRebalancerEvents.sol";

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IRebalancer } from "src/interfaces/Rebalancer/IRebalancer.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

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
     * @custom:then Each function should revert with the same custom Ownable error
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
        protocol.setRebalancer(IRebalancer(address(this)));

        vm.expectRevert(customError);
        protocol.setSecurityDepositValue(0);

        vm.expectRevert(customError);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0);

        vm.expectRevert(customError);
        protocol.setMinLongPosition(100 ether);

        vm.expectRevert(customError);
        protocol.setPositionFeeBps(0);

        vm.expectRevert(customError);
        protocol.setVaultFeeBps(0);

        vm.expectRevert(customError);
        protocol.setRebalancerBonusBps(0);
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because zero
     */
    function test_RevertWhen_setOracleMiddlewareWithZero() external adminPrank {
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
    function test_setOracleMiddleware() external adminPrank {
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
    function test_RevertWhen_setMinLeverageWithZero() external adminPrank {
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
    function test_RevertWhen_setMinLeverageWithMax() external adminPrank {
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
    function test_setMinLeverage() external adminPrank {
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
    function test_RevertWhen_setMaxLeverageWithMin() external adminPrank {
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
    function test_RevertWhen_setMaxLeverageWithMax() external adminPrank {
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
    function test_setMaxLeverage() external adminPrank {
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
     * @custom:scenario Call "setValidationDeadline" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because lower than min disallowed
     */
    function test_RevertWhen_setValidationDeadlineWithMin() external adminPrank {
        // validationDeadline lower than min disallowed
        vm.expectRevert(UsdnProtocolInvalidValidationDeadline.selector);
        // set validationDeadline
        protocol.setValidationDeadline(59);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setValidationDeadlineWithMax() external adminPrank {
        // validationDeadline greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidValidationDeadline.selector);
        // set validationDeadline
        protocol.setValidationDeadline(365 days + 1);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setValidationDeadline() external adminPrank {
        // cache the new validationDeadline value to assign
        uint256 expectedNewValue = 61;
        // expected event
        vm.expectEmit();
        emit ValidationDeadlineUpdated(expectedNewValue);
        // assign new validationDeadline value
        protocol.setValidationDeadline(expectedNewValue);
        // check new value is equal to the expected value
        assertEq(protocol.getValidationDeadline(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then Revert because greater than max
     */
    function test_RevertWhen_setLiquidationPenaltyMax() external adminPrank {
        // liquidationPenalty greater than max disallowed
        vm.expectRevert(UsdnProtocolInvalidLiquidationPenalty.selector);
        // set liquidationPenalty
        protocol.setLiquidationPenalty(16);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setLiquidationPenalty() external adminPrank {
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
    function test_RevertWhen_setSafetyMarginBpsWithMax() external adminPrank {
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
    function test_setSafetyMarginBps() external adminPrank {
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
    function test_RevertWhen_setLiquidationIterationWithMax() external adminPrank {
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
    function test_setLiquidationIteration() external adminPrank {
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
    function test_RevertWhen_setEMAPeriodWithMax() external adminPrank {
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
    function test_setEMAPeriod() external adminPrank {
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
    function test__RevertWhen_setFundingSFWithMax() external adminPrank {
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
    function test_setFundingSF() external adminPrank {
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
    function test_RevertWhen_setFeeBpsWithMax() external adminPrank {
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
    function test_setFeeBps() external adminPrank {
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
    function test_RevertWhen_setSdexBurnOnDepositRatioWithMax() external adminPrank {
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
    function test_setSdexBurnOnDepositRatio() external adminPrank {
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
    function test_RevertWhen_setFeeCollectorWithZero() external adminPrank {
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
    function test_setFeeCollector() external adminPrank {
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
    function test_setFeeThreshold() external adminPrank {
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
    function test_RevertWhen_setLiquidationRewardsManagerWithZero() external adminPrank {
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
    function test_setLiquidationRewardsManager() external adminPrank {
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
     * @custom:then getRebalancer returns the zero address
     */
    function test_setRebalancerWithZeroAddress() external adminPrank {
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
    function test_setRebalancer() external adminPrank {
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
    function test_setSecurityDepositValue() external adminPrank {
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
    function test_setSecurityDepositValue_zero() external adminPrank {
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
     * @custom:scenario Call "setExpoImbalanceLimits" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function
     * @custom:then The value should be updated
     */
    function test_setExpoImbalanceLimits() external adminPrank {
        // limit basis point to assign
        uint256 expectedNewLimitBps = 0;
        // signed limit basis point
        int256 expectedSignedLimitBps = int256(expectedNewLimitBps);

        // expected event
        vm.expectEmit();
        emit ImbalanceLimitsUpdated(expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps);

        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(
            expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps, expectedNewLimitBps
        );

        // get signed limits basis point
        (int256 openLimitBps, int256 depositLimitBps, int256 withdrawalLimitBps, int256 closeLimitBps) =
            protocol.getExpoImbalanceLimits();

        // assert values are updated
        assertEq(openLimitBps, expectedSignedLimitBps, "open limit");
        assertEq(depositLimitBps, expectedSignedLimitBps, "deposit limit");
        assertEq(withdrawalLimitBps, expectedSignedLimitBps, "withdrawal limit");
        assertEq(closeLimitBps, expectedSignedLimitBps, "close limit");
    }

    /**
     * @custom:scenario Call "setExpoImbalanceLimits" from admin
     * @custom:given The initial usdnProtocol state from admin wallet
     * @custom:when Admin wallet triggers admin contract function with below min values
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_setExpoImbalanceLimitsLow() external adminPrank {
        protocol.setExpoImbalanceLimits(2, 2, 0, 0);

        // open and deposit limits basis point
        (int256 openLimitBps, int256 depositLimitBps,,) = protocol.getExpoImbalanceLimits();

        uint256 withdrawalLimitBpsBelowOpen = uint256(openLimitBps - 1);
        // expected revert
        vm.expectRevert(UsdnProtocolInvalidExpoImbalanceLimit.selector);
        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(uint256(openLimitBps), uint256(depositLimitBps), withdrawalLimitBpsBelowOpen, 0);

        uint256 closeLimitBpsBelowDeposit = uint256(depositLimitBps - 1);
        // expected revert
        vm.expectRevert(UsdnProtocolInvalidExpoImbalanceLimit.selector);
        // set expo imbalance limits basis point
        protocol.setExpoImbalanceLimits(uint256(openLimitBps), uint256(depositLimitBps), 0, closeLimitBpsBelowDeposit);
    }

    /**
     * @custom:scenario Call "setMinLongPosition" from admin
     * @custom:given The initial usdnProtocol state
     * @custom:when Admin wallet triggers the function
     * @custom:then The value should be updated
     */
    function test_setMinLongPosition() external adminPrank {
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
     * @custom:given The initial usdnProtocol state
     * @custom:when Admin wallet triggers the function
     * @custom:then The value should be updated
     */
    function test_setMinLongPosition_rebalancerUpdate() external {
        params = DEFAULT_PARAMS;
        params.flags.enableRebalancer = true;
        params.flags.enableLongLimit = true;
        _setUp(params);

        uint256 newValue = 1 ether;
        assertGt(rebalancer.getMinAssetDeposit(), newValue);

        // expected event
        vm.expectEmit();
        emit MinLongPositionUpdated(newValue);
        vm.expectEmit();
        emit MinAssetDepositUpdated(newValue);

        // set minimum long position
        vm.prank(ADMIN);
        protocol.setMinLongPosition(newValue);
        // assert that the new values are equal to the expected values
        assertEq(protocol.getMinLongPosition(), newValue);
        assertEq(rebalancer.getMinAssetDeposit(), newValue);
    }

    /**
     * @custom:scenario Call `setPositionFeeBps` as admin
     * @custom:when The admin sets the position fee between 0 and 2000 bps
     * @custom:then The position fee should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setPositionFeeBps() external adminPrank {
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
    function test_RevertWhen_setPositionFeeTooHigh() external adminPrank {
        vm.expectRevert(UsdnProtocolInvalidPositionFee.selector);
        protocol.setPositionFeeBps(2001);
    }

    /**
     * @custom:scenario Call `setVaultFeeBps` as admin
     * @custom:when The admin sets the vault fee between 0 and 2000 bps
     * @custom:then The vault fee should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setVaultFeeBps() external adminPrank {
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
    function test_RevertWhen_setVaultFeeTooHigh() external adminPrank {
        vm.expectRevert(UsdnProtocolInvalidVaultFee.selector);
        protocol.setVaultFeeBps(2001);
    }

    /**
     * @custom:scenario Call `setRebalancerBonusBps` as admin
     * @custom:when The admin sets the bonus between 0 and 10000 bps
     * @custom:then The bonus should be updated
     * @custom:and An event should be emitted with the corresponding new value
     */
    function test_setRebalancerBonusBps() external adminPrank {
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
    function test_RevertWhen_setRebalancerBonusTooHigh() external adminPrank {
        vm.expectRevert(UsdnProtocolInvalidRebalancerBonus.selector);
        protocol.setRebalancerBonusBps(10_001);
    }
}
