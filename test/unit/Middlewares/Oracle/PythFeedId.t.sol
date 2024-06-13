// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";
import { PYTH_ETH_USD } from "../../../utils/Constants.sol";

/// @custom:feature The `getPythFeedId` function of `OracleMiddleware`
contract TestOracleMiddlewarePythFeedId is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `getPythFeedId` getter
     * @custom:when The result of the result of the function is compared to PYTH_ETH_USD
     * @custom:then It should succeed
     */
    function test_getPythFeedId() public {
        assertEq(oracleMiddleware.getPythFeedId(), PYTH_ETH_USD);
    }
}
