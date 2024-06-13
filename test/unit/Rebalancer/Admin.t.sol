// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
    function test_RevertWhen_nonAdminWalletCallAdminFunctions() external {
        // ownable contract custom error
        bytes memory customError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));

        vm.expectRevert(customError);
        rebalancer.setPositionMaxLeverage(0);

        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.setMinAssetDeposit(1);

        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.ownershipCallback(address(this), PositionId(0, 0, 0));

        vm.expectRevert(customError);
        rebalancer.setCloseImbalanceLimitBps(0);
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
    function test_setMinAssetDeposit() public {
        uint256 newValue = usdnProtocol.getMinLongPosition() + 1 ether;

        vm.prank(ADMIN);
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
    function test_RevertWhen_setMinAssetDeposit_Invalid() public {
        uint256 minLimit = usdnProtocol.getMinLongPosition();
        assertGt(minLimit, 0, "the minimum of the protocol should be greater than 0");

        vm.prank(ADMIN);
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
     * @custom:scenario Trying to set the max leverage lower than the USDN protocol's value
     * @custom:given A value lower than the USDN protocol's max leverage
     * @custom:when `setPositionMaxLeverage` is called with this value
     * @custom:then The call reverts with a {RebalancerInvalidMaxLeverage} error
     */
    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooLow() external adminPrank {
        uint256 minLeverage = usdnProtocol.getMinLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(minLeverage - 1);
    }

    /**
     * @custom:scenario Trying to set the max leverage lower than the USDN protocol's value
     * @custom:given A value lower than the USDN protocol's max leverage
     * @custom:when `setPositionMaxLeverage` is called with this value
     * @custom:then The call reverts with a {RebalancerInvalidMaxLeverage} error
     */
    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooHigh() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(maxLeverage + 1);
    }

    /**
     * @custom:scenario Trying to set the max leverage from an address that is not the owner
     * @custom:given The caller not being the owner
     * @custom:when `setPositionMaxLeverage` is called
     * @custom:then The call reverts with an {OwnableUnauthorizedAccount} error
     */
    function test_RevertWhen_setPositionMaxLeverageWithCallerNotTheOwner() external {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rebalancer.setPositionMaxLeverage(maxLeverage - 1);
    }

    /**
     * @custom:scenario Setting the max leverage of the rebalancer
     * @custom:given A value lower than the USDN protocol's max leverage
     * @custom:when {setPositionMaxLeverage} is called with this value
     * @custom:then The value of `_positionMaxLeverage` is updated
     * @custom:and A {PositionMaxLeverageUpdated} event is emitted
     */
    function test_setPositionMaxLeverage() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();
        uint256 newMaxLeverage = maxLeverage - 1;

        vm.expectEmit();
        emit PositionMaxLeverageUpdated(newMaxLeverage);
        rebalancer.setPositionMaxLeverage(newMaxLeverage);

        assertEq(rebalancer.getPositionMaxLeverage(), newMaxLeverage, "The max leverage should have been updated");
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
    function test_RevertWhen_ownershipCallbackOnFirstIteration() external adminPrank {
        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.ownershipCallback(address(this), PositionId(0, 0, 0));
    }
}
