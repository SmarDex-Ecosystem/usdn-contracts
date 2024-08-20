// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "../../../../utils/Constants.sol";
import { OracleMiddlewareWithRedstoneFixture } from "../../utils/Fixtures.sol";

import { IOracleMiddlewareErrors } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";

/**
 * @custom:feature The `setRedstoneRecentPriceDelay` function of `RedstoneOracle`
 */
contract TestSetRedstoneRecentPriceDelay is OracleMiddlewareWithRedstoneFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `setRedstoneRecentPriceDelay` functions from non contract admin
     * @custom:given The initial oracle middleware state
     * @custom:when Non admin wallet trigger `setRedstoneRecentPriceDelay`
     * @custom:then functions should revert with custom Ownable error
     */
    function test_RevertWhen_nonAdminWalletCallSetRedstoneRecentPriceDelay() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER_1, oracleMiddleware.ADMIN_ROLE()
            )
        );
        vm.prank(USER_1);
        oracleMiddleware.setRedstoneRecentPriceDelay(11);
    }

    /**
     * @custom:scenario Call `getRedstoneRecentPriceDelay` getter
     * @custom:given The initial oracle middleware state
     * @custom:when The result of the function is compared to 45
     * @custom:then It should succeed
     */
    function test_recentPriceDelay() public view {
        assertEq(oracleMiddleware.getRedstoneRecentPriceDelay(), 45);
    }

    /**
     * @custom:scenario Call `setRedstoneRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setRedstoneRecentPriceDelay` is executed with a too high value
     * @custom:then It should revert
     */
    function test_RevertWhen_setRedstoneRecentPriceDelayTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleMiddlewareErrors.OracleMiddlewareInvalidRecentPriceDelay.selector, 10 minutes + 1
            )
        );
        oracleMiddleware.setRedstoneRecentPriceDelay(10 minutes + 1);
    }

    /**
     * @custom:scenario Call `setRedstoneRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setRedstoneRecentPriceDelay` is executed with a too low value
     * @custom:then It should revert
     */
    function test_RevertWhen_setRedstoneRecentPriceDelayTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleMiddlewareErrors.OracleMiddlewareInvalidRecentPriceDelay.selector, 9)
        );
        oracleMiddleware.setRedstoneRecentPriceDelay(9);
    }

    /**
     * @custom:scenario Call `setRedstoneRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setRedstoneRecentPriceDelay` is executed with a correct value
     * @custom:then It should emit RecentPriceDelayUpdated event
     * @custom:and It should success
     */
    function test_setRedstoneRecentPriceDelay() public {
        vm.expectEmit();
        emit IOracleMiddlewareEvents.RedstoneRecentPriceDelayUpdated(10);
        oracleMiddleware.setRedstoneRecentPriceDelay(10);
        assertEq(oracleMiddleware.getRedstoneRecentPriceDelay(), 10);
    }
}
