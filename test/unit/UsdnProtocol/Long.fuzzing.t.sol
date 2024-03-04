// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests for the long part of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolFuzzingLong is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculations of `_positionValue`
     * @custom:given An opening price between $1000 and $100 000
     * @custom:and an amount between 0.1 and 100 000 ether
     * @custom:and a leverage between the protocol's min and max values
     * @custom:when _positionValue is called
     * @custom:then The returned value is equal to the expected value.
     */
    function testFuzz_positionValue(uint256 amount, uint256 currentPrice, uint256 leverage) public {
        uint256 priceAtOpening = 1000 ether;
        uint256 levDecimals = 10 ** protocol.LEVERAGE_DECIMALS();

        // Set some boundaries for the fuzzed inputs
        amount = bound(amount, 0.1 ether, 100_000 ether);
        currentPrice = bound(currentPrice, priceAtOpening, priceAtOpening * 100);
        leverage = bound(leverage, protocol.getMinLeverage(), protocol.getMaxLeverage());

        // Start checks
        uint128 liqPrice = uint128(FixedPointMathLib.fullMulDiv(priceAtOpening, levDecimals, leverage));
        uint256 positionExpo = FixedPointMathLib.fullMulDiv(amount, leverage, levDecimals);
        uint256 expectedValue = FixedPointMathLib.fullMulDiv(positionExpo, (currentPrice - liqPrice), currentPrice);
        uint256 value = protocol.i_positionValue(uint128(currentPrice), liqPrice, uint128(positionExpo));
        assertEq(expectedValue, value, "Returned value is incorrect");
    }
}
