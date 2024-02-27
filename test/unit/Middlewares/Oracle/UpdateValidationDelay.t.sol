// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";

/**
 * @custom:feature The `updateValidationDelay` function of `OracleMiddleware`
 */
contract TestOracleMiddlewareUpdateValidationDelay is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `validationDelay` getter
     * @custom:when The result of the result of the function is compared to 24
     * @custom:then It should succeed
     */
    function test_validationDelay() public {
        assertEq(oracleMiddleware.validationDelay(), 24 seconds);
    }

    /**
     * @custom:scenario Call `validationDelay` getter
     * @custom:when The result of the result of the function is compared to 24
     * @custom:then It should succeed
     */
    function test_updateValidationDelay() public {
        assertEq(oracleMiddleware.validationDelay(), 24 seconds);

        oracleMiddleware.updateValidationDelay(48 seconds);

        assertEq(oracleMiddleware.validationDelay(), 48 seconds);
    }
}
