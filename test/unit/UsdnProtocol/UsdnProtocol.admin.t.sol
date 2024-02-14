// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";

import { UsdnProtocolBaseFixture, IUsdnProtocolErrors } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER } from "test/utils/Constants.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @custom:feature The functions admin of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolAdmin is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call both admin functions from non contract admin.
     * @custom:given The initial usdnProtocol state.
     * @custom:then Each functions should revert with the same custom Ownable error.
     */
    function test_nonAdminWalletEachFunctionsRevert() external {
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
        protocol.setFundingRatePerSecond(0);

        vm.expectRevert(customError);
        protocol.setLiquidationPenalty(0);

        vm.expectRevert(customError);
        protocol.setSafetyMargin(0);

        vm.expectRevert(customError);
        protocol.setLiquidationIteration(0);

        vm.expectRevert(customError);
        protocol.setEMAPeriod(0);

        vm.expectRevert(customError);
        protocol.setFundingSF(0);
    }

    /**
     * @custom:scenario Call "setOracleMiddleware" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because zero.
     */
    function test_setOracleMiddlewareRevertZero() external AdminPrank {
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
    function test_setOracleMiddleware() external AdminPrank {
        // random address
        address randAddress = address(1);
        // cache previous value
        IOracleMiddleware previousDefault = protocol.oracleMiddleware();
        // assert previous middleware different than randAddress
        assertTrue(address(previousDefault) != randAddress);
        // set middleware
        protocol.setOracleMiddleware(IOracleMiddleware(randAddress));
        // assert new middleware equal randAddress
        assertEq(address(protocol.oracleMiddleware()), randAddress);
    }

    /**
     * @custom:scenario Call "setMinLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because zero.
     */
    function test_setMinLeverageRevertZero() external AdminPrank {
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
    function test_setMinLeverageRevertMax() external AdminPrank {
        uint256 maxLeverage = protocol.maxLeverage();
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
    function test_setMinLeverage() external AdminPrank {
        // set new minLeverage
        // previous minLeverage value
        uint256 previousValue = protocol.minLeverage();
        // cache the new minLeverage value to assign
        uint256 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new minLeverage value
        protocol.setMinLeverage(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.minLeverage(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because lower than min.
     */
    function test_setMaxLeverageRevertMin() external AdminPrank {
        uint256 minLeverage = protocol.minLeverage();
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
    function test_setMaxLeverageRevertMax() external AdminPrank {
        // maxLeverage greater than max disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolMaxLeverageGreaterThanMax.selector);
        // set maxLeverage
        protocol.setMaxLeverage(100 * 10 ** 21 + 1);
    }

    /**
     * @custom:scenario Call "setMaxLeverage" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_setMaxLeverage() external AdminPrank {
        // previous maxLeverage value
        uint256 previousValue = protocol.maxLeverage();
        // cache the new maxLeverage value to assign
        uint256 expectedNewValue = protocol.minLeverage() + 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new maxLeverage value
        protocol.setMaxLeverage(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.maxLeverage(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because lower than min disallowed.
     */
    function test_validationDeadlineRevertMin() external AdminPrank {
        // validationDeadline lower than min (1 minute) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolValidationDeadlineLowerThanMin.selector);
        // set validationDeadline
        protocol.setValidationDeadline(59);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_validationDeadlineRevertMax() external AdminPrank {
        // validationDeadline greater than max ( 1 year ) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolValidationDeadlineGreaterThanMax.selector);
        // set validationDeadline
        protocol.setValidationDeadline(365 days + 1);
    }

    /**
     * @custom:scenario Call "setValidationDeadline" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_validationDeadline() external AdminPrank {
        // previous validationDeadline value
        uint256 previousValue = protocol.validationDeadline();
        // cache the new validationDeadline value to assign
        uint256 expectedNewValue = 61;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new validationDeadline value
        protocol.setValidationDeadline(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.validationDeadline(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_liquidationPenaltyRevertMax() external AdminPrank {
        // liquidationPenalty greater than max (15 tick spacing) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolLiquidationPenaltyGreaterThanMax.selector);
        // set liquidationPenalty
        protocol.setLiquidationPenalty(16);
    }

    /**
     * @custom:scenario Call "setLiquidationPenalty" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_liquidationPenalty() external AdminPrank {
        // previous liquidationPenalty value
        uint24 previousValue = protocol.liquidationPenalty();
        // cache the new liquidationPenalty value to assign
        uint24 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new liquidationPenalty value
        protocol.setLiquidationPenalty(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.liquidationPenalty(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setSafetyMargin" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_safetyMarginRevertMax() external AdminPrank {
        // safetyMargin greater than max (20%) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolSafetyMarginGreaterThanMax.selector);
        // set safetyMargin
        protocol.setSafetyMargin(2001);
    }

    /**
     * @custom:scenario Call "setSafetyMargin" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_safetyMargin() external AdminPrank {
        // previous safetyMargin value
        uint256 previousValue = protocol.safetyMargin();
        // cache the new safetyMargin value to assign
        uint256 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new safetyMargin value
        protocol.setSafetyMargin(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.safetyMargin(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setLiquidationIteration" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_liquidationIterationRevertMax() external AdminPrank {
        // liquidationIteration greater than max (10) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolLiquidationIterationGreaterThanMax.selector);
        // set liquidationIteration
        protocol.setLiquidationIteration(2001);
    }

    /**
     * @custom:scenario Call "setLiquidationIteration" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_liquidationIteration() external AdminPrank {
        // previous liquidationIteration value
        uint16 previousValue = protocol.liquidationIteration();
        // cache the new liquidationIteration value to assign
        uint16 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new liquidationIteration value
        protocol.setLiquidationIteration(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.liquidationIteration(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because zero.
     */
    function test_EMAPeriodRevertZero() external AdminPrank {
        // EMAPeriod 0 disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolZeroEMAPeriod.selector);
        // set EMAPeriod
        protocol.setEMAPeriod(0);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_EMAPeriodRevertMax() external AdminPrank {
        // EMAPeriod greater than max (3 months) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolEMAPeriodGreaterThanMax.selector);
        // set EMAPeriod
        protocol.setEMAPeriod(90 days + 1);
    }

    /**
     * @custom:scenario Call "setEMAPeriod" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_EMAPeriod() external AdminPrank {
        // previous EMAPeriod value
        uint128 previousValue = protocol.EMAPeriod();
        // cache the new EMAPeriod value to assign
        uint128 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new EMAPeriod value
        protocol.setEMAPeriod(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.EMAPeriod(), expectedNewValue);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because zero.
     */
    function test_fundingSFRevertZero() external AdminPrank {
        // fundingSF 0 disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolZeroFundingSF.selector);
        // set fundingSF
        protocol.setFundingSF(0);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Revert because greater than max.
     */
    function test_fundingSFRevertMax() external AdminPrank {
        // fundingSF greater than max (1) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolFundingSFGreaterThanMax.selector);
        // set fundingSF
        protocol.setFundingSF(1000 + 1);
    }

    /**
     * @custom:scenario Call "setFundingSF" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_fundingSF() external AdminPrank {
        // previous fundingSF value
        uint256 previousValue = protocol.fundingSF();
        // cache the new fundingSF value to assign
        uint256 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new fundingSF value
        protocol.setFundingSF(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.fundingSF(), expectedNewValue);
    }
}
