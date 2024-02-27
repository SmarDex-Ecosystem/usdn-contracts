// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";

/**
 * @custom:feature The `updateValidationDelay` function of `OracleMiddleware`
 */
contract TestOracleMiddlewareSetRecentPriceDelay is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `setRecentPriceDelay` functions from non contract admin
     * @custom:given The initial oracle middleware state
     * @custom:when Non admin wallet trigger `setRecentPriceDelay`
     * @custom:then functions should revert with custom Ownable error
     */
    function test_RevertWhen_nonAdminWalletCallSetRecentPriceDelay() external {
        vm.startPrank(USER_1);
        // Ownable contract custom error
        bytes memory customError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1);
        vm.expectRevert(customError);
        oracleMiddleware.setRecentPriceDelay(11);
        vm.stopPrank();
    }

    /**
     * @custom:scenario Call `getRecentPriceDelay` getter
     * @custom:given The initial oracle middleware state
     * @custom:when The result of the function is compared to 45
     * @custom:then It should succeed
     */
    function test_recentPriceDelay() public {
        assertEq(oracleMiddleware.getRecentPriceDelay(), 45);
    }

    /**
     * @custom:scenario Call `setRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setRecentPriceDelay` is executed with a too high value
     * @custom:then It should revert
     */
    function test_RevertWhen_setRecentPriceDelayTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleMiddlewareErrors.OracleMiddlewareInvalidRecentPriceDelay.selector, 10 minutes + 1
            )
        );
        oracleMiddleware.setRecentPriceDelay(10 minutes + 1);
    }

    /**
     * @custom:scenario Call `setRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setRecentPriceDelay` is executed with a too low value
     * @custom:then It should revert
     */
    function test_RevertWhen_setRecentPriceDelayTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleMiddlewareErrors.OracleMiddlewareInvalidRecentPriceDelay.selector, 9)
        );
        oracleMiddleware.setRecentPriceDelay(9);
    }

    /**
     * @custom:scenario Call `setRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setRecentPriceDelay` is executed with a correct value
     * @custom:then It should emit RecentPriceDelayUpdated event
     * @custom:and It should success
     */
    function test_setRecentPriceDelay() public {
        vm.expectEmit();
        emit IOracleMiddlewareEvents.RecentPriceDelayUpdated(10);
        oracleMiddleware.setRecentPriceDelay(10);
        assertEq(oracleMiddleware.getRecentPriceDelay(), 10);
    }
}
