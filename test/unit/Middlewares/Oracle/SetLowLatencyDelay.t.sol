// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/// @custom:feature The `setLowLatencyDelay` function of `OracleMiddleware`
contract TestOracleMiddlewareSetLowLatencyDelay is OracleMiddlewareBaseFixture {
    uint16 constant DEFAULT_LOW_LATENCY_DELAY = 20 minutes;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `getLowLatencyDelay` getter
     * @custom:when The function is called
     * @custom:then It should return the default value
     */
    function test_getLowLatencyDelay() public {
        assertEq(oracleMiddleware.getLowLatencyDelay(), DEFAULT_LOW_LATENCY_DELAY);
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay` from non admin
     * @custom:when The function is called from an account that is not the owner
     * @custom:then It should revert
     */
    function test_RevertWhen_setLowLatencyDelayNonAdmin() public {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        oracleMiddleware.setLowLatencyDelay(DEFAULT_LOW_LATENCY_DELAY);
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay` lower than minimum
     * @custom:when The function is called with a value that is below the minimum allowed
     * @custom:then It should revert with `OracleMiddlewareInvalidLowLatencyDelay`
     */
    function test_RevertWhen_setLowLatencyDelayMin() public {
        vm.expectRevert(IOracleMiddlewareErrors.OracleMiddlewareInvalidLowLatencyDelay.selector);
        oracleMiddleware.setLowLatencyDelay(15 minutes - 1);
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay` higher than maximum
     * @custom:when The function is called with a value that is above the maximum allowed
     * @custom:then It should revert with `OracleMiddlewareInvalidLowLatencyDelay`
     */
    function test_RevertWhen_setLowLatencyDelayMax() public {
        vm.expectRevert(IOracleMiddlewareErrors.OracleMiddlewareInvalidLowLatencyDelay.selector);
        oracleMiddleware.setLowLatencyDelay(90 minutes + 1);
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay`
     * @custom:when The function is called with a correct value
     * @custom:then It should update the value
     */
    function test_setLowLatencyDelay() public {
        vm.expectEmit();
        emit IOracleMiddlewareEvents.LowLatencyDelayUpdated(DEFAULT_LOW_LATENCY_DELAY);
        oracleMiddleware.setLowLatencyDelay(DEFAULT_LOW_LATENCY_DELAY);
        assertEq(
            oracleMiddleware.getLowLatencyDelay(), DEFAULT_LOW_LATENCY_DELAY, "Low latency delay should be updated"
        );
    }
}
