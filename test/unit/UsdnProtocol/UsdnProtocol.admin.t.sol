// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";

import {
    UsdnProtocolBaseFixture,
    IUsdnProtocolErrors,
    IUsdnProtocolEvents
} from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The admin functions of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolAdmin is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call all admin functions from non contract admin.
     * @custom:given The initial usdnProtocol state.
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
        protocol.setFeeBps(0);

        vm.expectRevert(customError);
        protocol.setFeeCollector(address(this));

        vm.expectRevert(customError);
        protocol.setFeeThreshold(0);

        vm.expectRevert(customError);
        protocol.setLiquidationRewardsManager(ILiquidationRewardsManager(address(this)));
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because zero.
     */
    function test_RevertWhen_setOracleMiddlewareWithZero() external adminPrank {
        // zero address disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolZeroMiddlewareAddress.selector);
        // set middleware
        protocol.setOracleMiddleware(IOracleMiddleware(address(0)));
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setOracleMiddleware() external adminPrank {
        // random address
        address randAddress = address(1);
        // cache previous value
        IOracleMiddleware previousDefault = protocol.getOracleMiddleware();
        // assert previous middleware different than randAddress
        assertTrue(address(previousDefault) != randAddress);
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.OracleMiddlewareUpdated(randAddress);
        // set middleware
        protocol.setOracleMiddleware(IOracleMiddleware(randAddress));
        // assert new middleware equal randAddress
        assertEq(address(protocol.getOracleMiddleware()), randAddress);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because zero.
     */
    function test_RevertWhen_setMinLeverageWithZero() external adminPrank {
        // minLeverage zero disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolZeroMinLeverage.selector);
        // set minLeverage
        protocol.setMinLeverage(0);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setMinLeverageWithMax() external adminPrank {
        uint256 maxLeverage = protocol.getMaxLeverage();
        // minLeverage higher than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolMinLeverageGreaterThanMax.selector);
        // set minLeverage
        protocol.setMinLeverage(maxLeverage);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setMinLeverage() external adminPrank {
        // set new minLeverage
        // previous minLeverage value
        uint256 previousValue = protocol.getMinLeverage();
        // cache the new minLeverage value to assign
        uint256 expectedNewValue = 10 ** protocol.LEVERAGE_DECIMALS() + 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because lower than min.
     */
    function test_RevertWhen_setMaxLeverageWithMin() external adminPrank {
        uint256 minLeverage = protocol.getMinLeverage();
        // maxLeverage lower than min disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolMaxLeverageLowerThanMin.selector);
        // set maxLeverage
        protocol.setMaxLeverage(minLeverage);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setMaxLeverageWithMax() external adminPrank {
        // cache limit
        uint256 aboveLimit = 100 * 10 ** protocol.LEVERAGE_DECIMALS() + 1;
        // maxLeverage greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolMaxLeverageGreaterThanMax.selector);
        // set maxLeverage
        protocol.setMaxLeverage(aboveLimit);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setMaxLeverage() external adminPrank {
        // previous maxLeverage value
        uint256 previousValue = protocol.getMaxLeverage();
        // cache the new maxLeverage value to assign
        uint256 expectedNewValue = protocol.getMinLeverage() + 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because lower than min disallowed.
     */
    function test_RevertWhen_setValidationDeadlineWithMin() external adminPrank {
        // validationDeadline lower than min disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolValidationDeadlineLowerThanMin.selector);
        // set validationDeadline
        protocol.setValidationDeadline(59);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setValidationDeadlineWithMax() external adminPrank {
        // validationDeadline greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolValidationDeadlineGreaterThanMax.selector);
        // set validationDeadline
        protocol.setValidationDeadline(365 days + 1);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setValidationDeadline() external adminPrank {
        // previous validationDeadline value
        uint256 previousValue = protocol.getValidationDeadline();
        // cache the new validationDeadline value to assign
        uint256 expectedNewValue = 61;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setLiquidationPenaltyMax() external adminPrank {
        // liquidationPenalty greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolLiquidationPenaltyGreaterThanMax.selector);
        // set liquidationPenalty
        protocol.setLiquidationPenalty(16);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setLiquidationPenalty() external adminPrank {
        // previous liquidationPenalty value
        uint24 previousValue = protocol.getLiquidationPenalty();
        // cache the new liquidationPenalty value to assign
        uint24 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setSafetyMarginBpsWithMax() external adminPrank {
        // safetyMargin greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolSafetyMarginBpsGreaterThanMax.selector);
        // set safetyMargin
        protocol.setSafetyMarginBps(2001);
    }

    /**
     * @custom:scenario Call "setSafetyMarginBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setSafetyMarginBps() external adminPrank {
        // previous safetyMargin value
        uint256 previousValue = protocol.getSafetyMarginBps();
        // cache the new safetyMargin value to assign
        uint256 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setLiquidationIterationWithMax() external adminPrank {
        uint16 aboveMax = protocol.MAX_LIQUIDATION_ITERATION() + 1;
        // liquidationIteration greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolLiquidationIterationGreaterThanMax.selector);
        // set liquidationIteration
        protocol.setLiquidationIteration(aboveMax);
    }

    /**
     * @custom:scenario Call "setLiquidationIteration" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setLiquidationIteration() external adminPrank {
        // previous liquidationIteration value
        uint16 previousValue = protocol.getLiquidationIteration();
        // cache the new liquidationIteration value to assign
        uint16 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because zero.
     */
    function test_RevertWhen_setEMAPeriodWithZero() external adminPrank {
        // EMAPeriod zero disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolZeroEMAPeriod.selector);
        // set EMAPeriod
        protocol.setEMAPeriod(0);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setEMAPeriodWithMax() external adminPrank {
        // EMAPeriod greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolEMAPeriodGreaterThanMax.selector);
        // set EMAPeriod
        protocol.setEMAPeriod(90 days + 1);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setEMAPeriod() external adminPrank {
        // previous EMAPeriod value
        uint128 previousValue = protocol.getEMAPeriod();
        // cache the new EMAPeriod value to assign
        uint128 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because greater than max.
     */
    function test__RevertWhen_setFundingSFWithMax() external adminPrank {
        // cached limit
        uint256 aboveLimit = 10 ** protocol.FUNDING_SF_DECIMALS() + 1;
        // fundingSF greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolFundingSFGreaterThanMax.selector);
        // set fundingSF
        protocol.setFundingSF(aboveLimit);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setFundingSF() external adminPrank {
        // previous fundingSF value
        uint256 previousValue = protocol.getFundingSF();
        // cache the new fundingSF value to assign
        uint256 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.FundingSFUpdated(expectedNewValue);
        // assign new fundingSF value
        protocol.setFundingSF(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getFundingSF(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setFeeBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setFeeBpsWithMax() external adminPrank {
        // above max value
        uint16 aboveMax = uint16(protocol.BPS_DIVISOR()) + 1;
        // feeBps greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidProtocolFeeBps.selector);
        // set feeBps
        protocol.setFeeBps(aboveMax);
    }

    /**
     * @custom:scenario Call "setFeeBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setFeeBps() external adminPrank {
        // previous feeBps value
        uint16 previousValue = uint16(protocol.getProtocolFeeBps());
        // cache the new feeBps value to assign
        uint16 expectedNewValue;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.FeeBpsUpdated(expectedNewValue);
        // assign new feeBps value
        protocol.setFeeBps(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getProtocolFeeBps(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setFeeCollector" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
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
     * @custom:then Value should be updated.
     */
    function test_setFeeCollector() external adminPrank {
        // previous feeCollector address
        address previousValue = protocol.getFeeCollector();
        // cache the new feeCollector address to assign
        address expectedNewValue = address(this);
        // check new address to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Value should be updated.
     */
    function test_setFeeThreshold() external adminPrank {
        // previous feeThreshold value
        uint256 previousValue = protocol.getFeeThreshold();
        // cache the new feeThreshold value to assign
        uint256 expectedNewValue = type(uint256).max;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
     * @custom:then Revert because zero.
     */
    function test_RevertWhen_setLiquidationRewardsManagerWithZero() external adminPrank {
        // zero address disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolLiquidationRewardsManagerIsZeroAddress.selector);
        // set liquidation reward manager
        protocol.setLiquidationRewardsManager(ILiquidationRewardsManager(address(0)));
    }

    /**
     * @custom:scenario Call "setLiquidationRewardsManager" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setLiquidationRewardsManager() external adminPrank {
        // expected new value
        ILiquidationRewardsManager expectedNewValue = ILiquidationRewardsManager(address(this));
        // cache previous address
        ILiquidationRewardsManager previousDefault = protocol.getLiquidationRewardsManager();
        // assert previous liquidation reward manager different than expectedNewValue
        assertTrue(address(previousDefault) != address(expectedNewValue));
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidationRewardsManagerUpdated(address(expectedNewValue));
        // set liquidation reward manager
        protocol.setLiquidationRewardsManager(expectedNewValue);
        // assert new liquidation reward manager equal expectedNewValue
        assertEq(address(protocol.getLiquidationRewardsManager()), address(expectedNewValue));
    }
}
