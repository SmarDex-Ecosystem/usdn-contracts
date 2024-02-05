// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";

/**
 * @custom:feature The `decimals` function of `OracleMiddleware`
 */
contract TestOracleMiddlewareDecimals is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `decimals` getter
     * @custom:when The result of the result of the function is compared to 18
     * @custom:then It should succeed
     */
    function test_decimals() public {
        assertEq(oracleMiddleware.decimals(), 18);
    }

    /**
     * @custom:scenario Call `pythDecimals` getter
     * @custom:when The result of the result of the function is compared to 8
     * @custom:then It should succeed
     */
    function test_pythDecimals() public {
        assertEq(oracleMiddleware.pythDecimals(), 8);
    }

    /**
     * @custom:scenario Call `chainlinkDecimals` getter
     * @custom:when The result of the result of the function is compared to 8
     * @custom:then It should succeed
     */
    function test_chainlinkDecimals() public {
        assertEq(oracleMiddleware.chainlinkDecimals(), 8);
    }
}
