// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";

import { IOracleMiddlewareErrors } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";

/**
 * @custom:feature The `setPythRecentPriceDelay` function of `OracleMiddleware`
 */
contract TestOracleMiddlewareSetPythRecentPriceDelay is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `setPythRecentPriceDelay` functions from a wallet without the right role
     * @custom:given The initial oracle middleware state
     * @custom:when A wallet without right role trigger `setPythRecentPriceDelay`
     * @custom:then functions should revert with custom "AccessControlUnauthorizedAccount" error
     */
    function test_RevertWhen_nonAdminWalletCallSetPythRecentPriceDelay() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER_1, oracleMiddleware.ADMIN_ROLE()
            )
        );
        vm.prank(USER_1);
        oracleMiddleware.setPythRecentPriceDelay(11);
    }

    /**
     * @custom:scenario Call `getPythRecentPriceDelay` getter
     * @custom:given The initial oracle middleware state
     * @custom:when The result of the function is compared to 45
     * @custom:then It should succeed
     */
    function test_recentPriceDelay() public view {
        assertEq(oracleMiddleware.getPythRecentPriceDelay(), 45);
    }

    /**
     * @custom:scenario Call `setPythRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setPythRecentPriceDelay` is executed with a too high value
     * @custom:then It should revert
     */
    function test_RevertWhen_setPythRecentPriceDelayTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleMiddlewareErrors.OracleMiddlewareInvalidRecentPriceDelay.selector, 10 minutes + 1
            )
        );
        oracleMiddleware.setPythRecentPriceDelay(10 minutes + 1);
    }

    /**
     * @custom:scenario Call `setPythRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setPythRecentPriceDelay` is executed with a too low value
     * @custom:then It should revert
     */
    function test_RevertWhen_setPythRecentPriceDelayTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleMiddlewareErrors.OracleMiddlewareInvalidRecentPriceDelay.selector, 9)
        );
        oracleMiddleware.setPythRecentPriceDelay(9);
    }

    /**
     * @custom:scenario Call `setPythRecentPriceDelay`
     * @custom:given The initial oracle middleware state
     * @custom:when The `setPythRecentPriceDelay` is executed with a correct value
     * @custom:then It should emit PythRecentPriceDelayUpdated event
     * @custom:and It should success
     */
    function test_setPythRecentPriceDelay() public {
        vm.expectEmit();
        emit IOracleMiddlewareEvents.PythRecentPriceDelayUpdated(10);
        oracleMiddleware.setPythRecentPriceDelay(10);
        assertEq(oracleMiddleware.getPythRecentPriceDelay(), 10);
    }
}
