// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ADMIN } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src//UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The admin functions of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancerAdmin is RebalancerFixture {
    function setUp() public {
        super._setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                           Caller is not the owner                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Call all admin functions from a non-admin wallet
     * @custom:given A deployed rebalancer contract
     * @custom:when Non-admin wallet triggers admin contract functions
     * @custom:then The functions should revert with an {Ownable.OwnableUnauthorizedAccount} error
     * @custom:or The functions should revert with a {RebalancerUnauthorized} error
     */
    function test_RevertWhen_nonAdminWalletCallAdminFunctions() public {
        // ownable contract custom error
        bytes memory customError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));

        vm.expectRevert(customError);
        rebalancer.setPositionMaxLeverage(0);

        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.setMinAssetDeposit(1);

        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.ownershipCallback(address(this), Types.PositionId(0, 0, 0));

        vm.expectRevert(customError);
        rebalancer.setTimeLimits(0, 0, 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                               minAssetDeposit                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Set of the `_minAssetDeposit` value of the rebalancer contract
     * @custom:given A deployed rebalancer contract
     * @custom:when The setter is called with a valid new value
     * @custom:then The value should have changed
     */
    function test_setMinAssetDeposit() public adminPrank {
        uint256 newValue = usdnProtocol.getMinLongPosition() + 1 ether;

        vm.expectEmit();
        emit MinAssetDepositUpdated(newValue);
        rebalancer.setMinAssetDeposit(newValue);
        assertEq(newValue, rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario Try to set the `_minAssetDeposit` value to an amount lower than the USDN Protocol
     * getMinLongPosition
     * @custom:given A deployed rebalancer contract
     * @custom:when The setter is called with a value lower than `protocol.getMinLongPosition()`
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_setMinAssetDeposit_Invalid() public adminPrank {
        uint256 minLimit = usdnProtocol.getMinLongPosition();
        assertGt(minLimit, 0, "the minimum of the protocol should be greater than 0");

        vm.expectRevert(RebalancerInvalidMinAssetDeposit.selector);
        rebalancer.setMinAssetDeposit(minLimit - 1);
    }

    /**
     * @custom:scenario Try to set the `_minAssetDeposit` value without being the admin
     * @custom:given A deployed rebalancer contract
     * @custom:when The setter is called by an unauthorized account
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_setMinAssetDeposit_NotAdmin() public {
        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.setMinAssetDeposit(1);
    }

    /* -------------------------------------------------------------------------- */
    /*                             positionMaxLeverage                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Trying to set the maximum leverage higher than the USDN protocol's value
     * @custom:given A value higher than the USDN protocol's maximum leverage
     * @custom:when `setPositionMaxLeverage` is called with this value
     * @custom:then The call reverts with a {RebalancerInvalidMaxLeverage} error
     */
    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooHigh() public adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(maxLeverage + 1);
    }

    /**
     * @custom:scenario Trying to set the maximum leverage equal to the rebalancer minimum leverage value defined by
     * the USDN protocol
     * @custom:given A value equal to the USDN protocol's minimum leverage
     * @custom:when `setPositionMaxLeverage` is called with this value
     * @custom:then The call reverts with a {RebalancerInvalidMaxLeverage} error
     */
    function test_RevertWhen_setPositionMaxLeverageLowerThanMinLeverage() public adminPrank {
        uint256 minLeverage = usdnProtocol.REBALANCER_MIN_LEVERAGE();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(minLeverage);
    }

    /**
     * @custom:scenario Setting the maximum leverage of the rebalancer
     * @custom:given A value lower than the USDN protocol's maximum leverage
     * @custom:when {setPositionMaxLeverage} is called with this value
     * @custom:then The value of `_positionMaxLeverage` is updated
     * @custom:and A {PositionMaxLeverageUpdated} event is emitted
     */
    function test_setPositionMaxLeverage() public adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();
        uint256 newMaxLeverage = maxLeverage - 1;

        vm.expectEmit();
        emit PositionMaxLeverageUpdated(newMaxLeverage);
        rebalancer.setPositionMaxLeverage(newMaxLeverage);

        assertEq(rebalancer.getPositionMaxLeverage(), newMaxLeverage, "The maximum leverage should have been updated");
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Time limits                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Set the time limits of the rebalancer contract
     * @custom:given We are the owner
     * @custom:when We call the setter with valid values
     * @custom:then The values should have changed
     * @custom:and The correct event should have been emitted
     */
    function test_setTimeLimits() public adminPrank {
        uint80 newValidationDelay = 0;
        uint80 newValidationDeadline = 5 minutes;
        uint80 newActionCooldown = 48 hours;

        vm.expectEmit();
        emit TimeLimitsUpdated(newValidationDelay, newValidationDeadline, newActionCooldown);
        rebalancer.setTimeLimits(newValidationDelay, newValidationDeadline, newActionCooldown);

        assertEq(rebalancer.getTimeLimits().validationDelay, newValidationDelay, "validation delay");
        assertEq(rebalancer.getTimeLimits().validationDeadline, newValidationDeadline, "validation deadline");
        assertEq(rebalancer.getTimeLimits().actionCooldown, newActionCooldown, "action cooldown");
    }

    /**
     * @custom:scenario Try to set the time limits with a delay that is too small (equal to the deadline)
     * @custom:given We are the owner
     * @custom:when We call the setter with a delay that is too small (equal to the deadline)
     * @custom:then The transaction reverts with a {RebalancerInvalidTimeLimits} error
     */
    function test_RevertWhen_setTimeLimitsDelayTooSmall() public adminPrank {
        vm.expectRevert(RebalancerInvalidTimeLimits.selector);
        rebalancer.setTimeLimits(5 minutes, 5 minutes, 48 hours);
    }

    /**
     * @custom:scenario Try to set the time limits with a deadline that is too small
     * @custom:given We are the owner
     * @custom:when We call the setter with a deadline that is too small
     * @custom:then The transaction reverts with a {RebalancerInvalidTimeLimits} error
     */
    function test_RevertWhen_setTimeLimitsDeadlineTooSmall() public adminPrank {
        vm.expectRevert(RebalancerInvalidTimeLimits.selector);
        rebalancer.setTimeLimits(1 minutes, 1 minutes + 59 seconds, 48 hours);
    }

    /**
     * @custom:scenario Try to set the time limits with a cooldown that is too small
     * @custom:given We are the owner
     * @custom:when We call the setter with a cooldown that is too small (smaller than the deadline)
     * @custom:then The transaction reverts with a {RebalancerInvalidTimeLimits} error
     */
    function test_RevertWhen_setTimeLimitsCooldownTooSmall() public adminPrank {
        vm.expectRevert(RebalancerInvalidTimeLimits.selector);
        rebalancer.setTimeLimits(0, 5 minutes, 5 minutes - 1);
    }

    /**
     * @custom:scenario Try to set the time limits with a cooldown that is too big
     * @custom:given We are the owner
     * @custom:when We call the setter with a cooldown that is too big
     * @custom:then The transaction reverts with a {RebalancerInvalidTimeLimits} error
     */
    function test_RevertWhen_setTimeLimitsCooldownTooBig() public adminPrank {
        vm.expectRevert(RebalancerInvalidTimeLimits.selector);
        rebalancer.setTimeLimits(0, 5 minutes, 48 hours + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                             ownershipCallback                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Call the `ownershipCallback()` function
     * @custom:given A deployed rebalancer contract
     * @custom:when The function `ownershipCallback()` is called on the first iteration of the rebalancer contract
     * @custom:then The functions should revert with an {Ownable.OwnableUnauthorizedAccount} error
     */
    function test_RevertWhen_ownershipCallbackOnFirstIteration() public adminPrank {
        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.ownershipCallback(address(this), Types.PositionId(0, 0, 0));
    }
}
