// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The `updateValidationDelay` function of `OracleMiddleware`
 */
contract TestOracleMiddlewareUpdateValidationDelay is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `getValidationDelay` getter
     * @custom:when The result of the result of the function is compared to 24
     * @custom:then It should succeed
     */
    function test_validationDelay() public view {
        assertEq(oracleMiddleware.getValidationDelay(), 24 seconds);
    }

    /**
     * @custom:scenario Call `getValidationDelay` getter
     * @custom:when The result of the result of the function is compared to 24
     * @custom:then It should succeed
     */
    function test_updateValidationDelay() public {
        assertEq(oracleMiddleware.getValidationDelay(), 24 seconds);

        oracleMiddleware.setValidationDelay(48 seconds);

        assertEq(oracleMiddleware.getValidationDelay(), 48 seconds);
    }
}
