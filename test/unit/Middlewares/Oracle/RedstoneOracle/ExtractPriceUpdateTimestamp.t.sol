// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";
import { REDSTONE_ETH_TIMESTAMP, REDSTONE_ETH_DATA } from "test/unit/Middlewares/utils/Constants.sol";

/**
 * @custom:feature The `extractPriceUpdateTimestamp` function of `RedstoneOracle`
 */
contract TestRedstoneOracleExtractPriceUpdateTimestamp is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Check that `extractPriceUpdateTimestamp` function returns the correct timestamp
     * @custom:given The calldata with a known timestamp and signature
     * @custom:when The `extractPriceUpdateTimestamp` function is called
     * @custom:then It should succeed
     */
    function test_extractPriceUpdateTimestamp() public {
        assertEq(
            oracleMiddleware.i_extractPriceUpdateTimestamp(REDSTONE_ETH_DATA),
            REDSTONE_ETH_TIMESTAMP,
            "timestamp should match calldata"
        );
    }
}
