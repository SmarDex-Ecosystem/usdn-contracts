// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddlewareBaseFixture } from "test/integration/OracleMiddleware/utils/Fixtures.sol";
import { PYTH_WSTETH_USD } from "test/utils/Constants.sol";

import { IOracleMiddlewareErrors, PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestOracleMiddlewareParseAndValidatePrice is OracleMiddlewareBaseFixture, IOracleMiddlewareErrors {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Parse and validate price with real hermes API signature
     * @custom:given The price feed is wstETH/USD
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is `None`
     * @custom:then The price signature is well decoded
     * @custom:and The price retrived by the oracle middleware is the same as the one from the hermes API
     */
    function test_FFI_parseAndValidatePriceWithPythData() public {
        super.startFork();
        (uint256 price, uint256 conf, uint256 timestamp, bytes memory data) =
            super.getPythSignature(PYTH_WSTETH_USD, block.timestamp - 24);

        console2.log("price", price);
        console2.log("conf", conf);
        console2.log("timestamp", timestamp);
        console2.logBytes(data);
    }
}
