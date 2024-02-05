// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { ETH_PRICE, ETH_CONF } from "test/unit/OracleMiddleware/utils/Constants.sol";
import { PYTH_WSTETH_USD } from "test/utils/Constants.sol";

import { PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @custom:feature The `priceID` function of `OracleMiddleware`
 */
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
        assertEq(oracleMiddleware.priceID(), PYTH_WSTETH_USD);
    }
}
