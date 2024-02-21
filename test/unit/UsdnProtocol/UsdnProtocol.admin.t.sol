// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";

import { UsdnProtocolBaseFixture, IUsdnProtocolErrors } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER } from "test/utils/Constants.sol";

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
        protocol.setLiquidationPenalty(0);

        vm.expectRevert(customError);
        protocol.setSafetyMarginBps(0);

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
        IOracleMiddleware previousDefault = protocol.getOracleMiddleware();
        // assert previous middleware different than randAddress
        assertTrue(address(previousDefault) != randAddress);
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
    function test_setMinLeverage() external AdminPrank {
        // set new minLeverage
        // previous minLeverage value
        uint256 previousValue = protocol.getMinLeverage();
        // cache the new minLeverage value to assign
        uint256 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
    function test_setMaxLeverageRevertMin() external AdminPrank {
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
        uint256 previousValue = protocol.getMaxLeverage();
        // cache the new maxLeverage value to assign
        uint256 expectedNewValue = protocol.getMinLeverage() + 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
        uint256 previousValue = protocol.getValidationDeadline();
        // cache the new validationDeadline value to assign
        uint256 expectedNewValue = 61;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
        uint24 previousValue = protocol.getLiquidationPenalty();
        // cache the new liquidationPenalty value to assign
        uint24 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
    function test_safetyMarginRevertMax() external AdminPrank {
        // safetyMargin greater than max (20%) disallowed
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolSafetyMarginBpsGreaterThanMax.selector);
        // set safetyMargin
        protocol.setSafetyMarginBps(2001);
    }

    /**
     * @custom:scenario Call "setSafetyMarginBps" from admin.
     * @custom:given The initial usdnProtocol state from admin wallet.
     * @custom:then Value should be updated.
     */
    function test_safetyMargin() external AdminPrank {
        // previous safetyMargin value
        uint256 previousValue = protocol.getSafetyMarginBps();
        // cache the new safetyMargin value to assign
        uint256 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
        uint16 previousValue = protocol.getLiquidationIteration();
        // cache the new liquidationIteration value to assign
        uint16 expectedNewValue = 0;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
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
        uint128 previousValue = protocol.getEMAPeriod();
        // cache the new EMAPeriod value to assign
        uint128 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new EMAPeriod value
        protocol.setEMAPeriod(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getEMAPeriod(), expectedNewValue);
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
        uint256 previousValue = protocol.getFundingSF();
        // cache the new fundingSF value to assign
        uint256 expectedNewValue = 1;
        // check new value to assign is not equal than current
        assertTrue(previousValue != expectedNewValue);
        // assign new fundingSF value
        protocol.setFundingSF(expectedNewValue);
        // check new value is equal than expected
        assertEq(protocol.getFundingSF(), expectedNewValue);
    }
}
