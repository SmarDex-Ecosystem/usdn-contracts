// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

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
        super._setUp(DEFAULT_PARAMS);
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
        protocolParams.setOracleMiddleware(IOracleMiddleware(address(1)));

        vm.expectRevert(customError);
        protocolParams.setMinLeverage(0);

        vm.expectRevert(customError);
        protocolParams.setMaxLeverage(0);

        vm.expectRevert(customError);
        protocolParams.setValidationDeadline(0);

        vm.expectRevert(customError);
        protocolParams.setLiquidationPenalty(0);

        vm.expectRevert(customError);
        protocolParams.setSafetyMarginBps(0);

        vm.expectRevert(customError);
        protocolParams.setLiquidationIteration(0);

        vm.expectRevert(customError);
        protocolParams.setEMAPeriod(0);

        vm.expectRevert(customError);
        protocolParams.setFundingSF(0);

        vm.expectRevert(customError);
        protocolParams.setProtocolFeeBps(0);

        vm.expectRevert(customError);
        protocolParams.setFeeCollector(address(this));

        vm.expectRevert(customError);
        protocolParams.setFeeThreshold(0);

        vm.expectRevert(customError);
        protocolParams.setLiquidationRewardsManager(ILiquidationRewardsManager(address(this)));
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
        protocolParams.setOracleMiddleware(IOracleMiddleware(address(0)));
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
        protocolParams.setOracleMiddleware(IOracleMiddleware(address(this)));
        // assert new middleware equal randAddress
        assertEq(address(protocolParams.getOracleMiddleware()), address(this));
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
        protocolParams.setMinLeverage(0);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because greater than max.
     */
    function test_RevertWhen_setMinLeverageWithMax() external adminPrank {
        uint256 maxLeverage = protocolParams.getMaxLeverage();
        // minLeverage higher than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidMinLeverage.selector);
        // set minLeverage
        protocolParams.setMinLeverage(maxLeverage);
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
        protocolParams.setMinLeverage(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getMinLeverage(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Revert because lower than min.
     */
    function test_RevertWhen_setMaxLeverageWithMin() external adminPrank {
        uint256 minLeverage = protocolParams.getMinLeverage();
        // maxLeverage lower than min disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidMaxLeverage.selector);
        // set maxLeverage
        protocolParams.setMaxLeverage(minLeverage);
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
        protocolParams.setMaxLeverage(aboveLimit);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:when Admin wallet trigger admin contract function.
     * @custom:then Value should be updated.
     */
    function test_setMaxLeverage() external adminPrank {
        // cache the new maxLeverage value to assign
        uint256 expectedNewValue = protocolParams.getMinLeverage() + 1;
        // expected event
        vm.expectEmit();
        emit IUsdnProtocolEvents.MaxLeverageUpdated(expectedNewValue);
        // assign new maxLeverage value
        protocolParams.setMaxLeverage(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getMaxLeverage(), expectedNewValue);
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
        protocolParams.setValidationDeadline(59);
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
        protocolParams.setValidationDeadline(365 days + 1);
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
        protocolParams.setValidationDeadline(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getValidationDeadline(), expectedNewValue);
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
        protocolParams.setLiquidationPenalty(16);
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
        protocolParams.setLiquidationPenalty(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getLiquidationPenalty(), expectedNewValue);
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
        protocolParams.setSafetyMarginBps(2001);
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
        protocolParams.setSafetyMarginBps(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getSafetyMarginBps(), expectedNewValue);
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
        protocolParams.setLiquidationIteration(aboveMax);
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
        protocolParams.setLiquidationIteration(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getLiquidationIteration(), expectedNewValue);
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
        protocolParams.setEMAPeriod(90 days + 1);
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
        protocolParams.setEMAPeriod(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getEMAPeriod(), expectedNewValue);
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
        protocolParams.setFundingSF(aboveLimit);
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
        protocolParams.setFundingSF(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getFundingSF(), expectedNewValue);
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
        protocolParams.setProtocolFeeBps(aboveMax);
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
        protocolParams.setProtocolFeeBps(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getProtocolFeeBps(), expectedNewValue);
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
        protocolParams.setFeeCollector(address(0));
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
        protocolParams.setFeeCollector(expectedNewValue);
        // check new address is equal than expected
        assertEq(protocolParams.getFeeCollector(), expectedNewValue);
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
        protocolParams.setFeeThreshold(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocolParams.getFeeThreshold(), expectedNewValue);
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
        protocolParams.setLiquidationRewardsManager(ILiquidationRewardsManager(address(0)));
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
        protocolParams.setLiquidationRewardsManager(expectedNewValue);
        // assert new liquidation reward manager equal expectedNewValue
        assertEq(address(protocolParams.getLiquidationRewardsManager()), address(expectedNewValue));
    }
}
