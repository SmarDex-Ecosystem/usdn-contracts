// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";
import { PYTH_WSTETH_USD } from "test/utils/Constants.sol";

/// @custom:feature The `priceID` function of `OracleMiddleware`
contract TestOracleMiddlewarePriceID is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `priceID` getter
     * @custom:when The result of the result of the function is compared to PYTH_WSTETH_USD
     * @custom:then It should succeed
     */
    function test_priceID() public {
        assertEq(oracleMiddleware.getPriceID(), PYTH_WSTETH_USD);
    }
}
