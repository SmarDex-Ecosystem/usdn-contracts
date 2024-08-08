// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { REDSTONE_ETH_DATA, REDSTONE_ETH_TIMESTAMP } from "../../utils/Constants.sol";
import { OracleMiddlewareWithRedstoneFixture } from "../../utils/Fixtures.sol";

/// @custom:feature The `extractPriceUpdateTimestamp` function of `RedstoneOracle`
contract TestRedstoneOracleExtractPriceUpdateTimestamp is OracleMiddlewareWithRedstoneFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Check that `extractPriceUpdateTimestamp` function returns the correct timestamp
     * @custom:given A valid Redstone update with a known timestamp
     * @custom:when The `extractPriceUpdateTimestamp` function is called with the Redstone message
     * @custom:then It should return the correct timestamp
     */
    function test_extractPriceUpdateTimestamp() public view {
        assertEq(
            oracleMiddleware.i_extractPriceUpdateTimestamp(REDSTONE_ETH_DATA),
            REDSTONE_ETH_TIMESTAMP,
            "timestamp should match calldata"
        );
    }
}
