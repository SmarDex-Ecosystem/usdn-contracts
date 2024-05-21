// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

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
     * @custom:then The functions should revert with an Ownable.OwnableUnauthorizedAccount error
     * @custom:or The functions should revert with a RebalancerUnauthorized error
     */
    function test_RevertWhen_nonAdminWalletCallAdminFunctions() external {
        // ownable contract custom error
        bytes memory customError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));

        vm.expectRevert(customError);
        rebalancer.setPositionMaxLeverage(0);

        vm.expectRevert(customError);
        rebalancer.increaseAssetAllowance(1);

        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.setMinAssetDeposit(1);
    }

    /* -------------------------------------------------------------------------- */
    /*                               minAssetDeposit                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Set of the _minAssetDeposit value of the rebalancer contract
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
     * @custom:scenario Try to set the _minAssetDeposit value to an amount lower than the USDN Protocol
     * getMinLongPosition
     * @custom:given A deployed rebalancer contract
     * @custom:when The setter is called with a value lower than protocol.getMinLongPosition()
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
     * @custom:scenario Try to set the _minAssetDeposit value without being the admin
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
     * @custom:when setPositionMaxLeverage is called with this value
     * @custom:then The call reverts with a RebalancerInvalidMaxLeverage error
     */
    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooLow() external adminPrank {
        uint256 minLeverage = usdnProtocol.getMinLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(minLeverage - 1);
    }

    /**
     * @custom:scenario Trying to set the max leverage lower than the USDN protocol's value
     * @custom:given A value lower than the USDN protocol's max leverage
     * @custom:when setPositionMaxLeverage is called with this value
     * @custom:then The call reverts with a RebalancerInvalidMaxLeverage error
     */
    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooHigh() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(maxLeverage + 1);
    }

    /**
     * @custom:scenario Trying to set the max leverage from an address that is not the owner
     * @custom:given The caller not being the owner
     * @custom:when setPositionMaxLeverage is called
     * @custom:then The call reverts with an OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_setPositionMaxLeverageWithCallerNotTheOwner() external {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rebalancer.setPositionMaxLeverage(maxLeverage - 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                           increaseAssetAllowance                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Increase the allowance of the protocol manually
     * @custom:given The initial allowance of the USDN protocol to transfer assets owned by the Rebalancer is 1 ether
     * @custom:when The allowance is increased by 1 ether
     * @custom:then The allowance becomes 2 ether
     * @custom:when The allowance is increased further by (uint256.max - 2 ether)
     * @custom:then The final allowance is uint256.max
     */
    function test_increaseAssetAllowance() external {
        vm.prank(address(rebalancer));
        wstETH.approve(address(usdnProtocol), 1 ether);

        assertEq(wstETH.allowance(address(rebalancer), address(usdnProtocol)), 1 ether, "initial allowance");

        vm.prank(ADMIN);
        rebalancer.increaseAssetAllowance(1 ether);

        assertEq(
            wstETH.allowance(address(rebalancer), address(usdnProtocol)), 2 ether, "allowance after adding 1 ether"
        );

        vm.prank(ADMIN);
        rebalancer.increaseAssetAllowance(type(uint256).max - 2 ether);

        assertEq(wstETH.allowance(address(rebalancer), address(usdnProtocol)), type(uint256).max, "final allowance");
    }
}
