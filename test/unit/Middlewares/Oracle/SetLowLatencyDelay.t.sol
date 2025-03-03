// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";
import { MockUsdnProtocol } from "../utils/MockUsdnProtocol.sol";

import { IOracleMiddlewareErrors } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/// @custom:feature The `setLowLatencyDelay` function of `OracleMiddleware`
contract TestOracleMiddlewareSetLowLatencyDelay is OracleMiddlewareBaseFixture {
    uint16 constant DEFAULT_LOW_LATENCY_DELAY = 20 minutes;
    IUsdnProtocol internal usdnProtocol;

    function setUp() public override {
        super.setUp();
        usdnProtocol = IUsdnProtocol(address(new MockUsdnProtocol()));
    }

    /**
     * @custom:scenario Call `getLowLatencyDelay` getter
     * @custom:when The function is called
     * @custom:then It should return the default value
     */
    function test_getLowLatencyDelay() public view {
        assertEq(oracleMiddleware.getLowLatencyDelay(), DEFAULT_LOW_LATENCY_DELAY);
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay` from an account that does not have the right role
     * @custom:when The function is called from an account that does not have the right role
     * @custom:then It should revert
     */
    function test_RevertWhen_setLowLatencyDelayNonAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER_1, oracleMiddleware.ADMIN_ROLE()
            )
        );
        vm.prank(USER_1);
        oracleMiddleware.setLowLatencyDelay(DEFAULT_LOW_LATENCY_DELAY, usdnProtocol);
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay` higher than maximum
     * @custom:when The function is called with a value that is above the maximum allowed
     * @custom:then It should revert with `OracleMiddlewareInvalidLowLatencyDelay`
     */
    function test_RevertWhen_setLowLatencyDelayMax() public {
        vm.expectRevert(IOracleMiddlewareErrors.OracleMiddlewareInvalidLowLatencyDelay.selector);
        oracleMiddleware.setLowLatencyDelay(90 minutes + 1, usdnProtocol);
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay`
     * @custom:when The function is called with a correct value
     * @custom:then It should update the value
     */
    function test_setLowLatencyDelay() public {
        vm.expectEmit();
        emit IOracleMiddlewareEvents.LowLatencyDelayUpdated(DEFAULT_LOW_LATENCY_DELAY);
        oracleMiddleware.setLowLatencyDelay(DEFAULT_LOW_LATENCY_DELAY, usdnProtocol);
        assertEq(
            oracleMiddleware.getLowLatencyDelay(), DEFAULT_LOW_LATENCY_DELAY, "Low latency delay should be updated"
        );
    }

    /**
     * @custom:scenario Call `setLowLatencyDelay` reverts with a value that is below validatorDeadline
     * @custom:when The function is called with validatorDeadline - 1
     * @custom:then It should revert with `OracleMiddlewareInvalidLowLatencyDelay`
     */
    function test_RevertWhen_setLowLatencyDelayBellowDeadline() public {
        uint128 validatorDeadline = 20 minutes;
        MockUsdnProtocol(address(usdnProtocol)).setLowLatencyValidatorDeadline(validatorDeadline);
        vm.expectRevert(IOracleMiddlewareErrors.OracleMiddlewareInvalidLowLatencyDelay.selector);
        oracleMiddleware.setLowLatencyDelay(uint16(validatorDeadline) - 1, usdnProtocol);
    }
}
