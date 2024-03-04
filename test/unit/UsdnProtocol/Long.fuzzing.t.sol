// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMath } from "src/libraries/TickMath.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests for the long part of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolFuzzingLong is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculations of `_positionValue`
     * @custom:given An opening price between the protocol's min price and type(uint128).max
     * @custom:and an amount between 1 wei and type(uint96).max ether
     * @custom:and a leverage between the protocol's min and max values
     * @custom:when _positionValue is called
     * @custom:then The returned value is equal to the expected value.
     */
    function testFuzz_positionValue(uint96 amount, uint128 priceAtOpening, uint128 currentPrice, uint256 leverage)
        public
    {
        uint256 levDecimals = 10 ** protocol.LEVERAGE_DECIMALS();

        // Set some boundaries for the fuzzed inputs
        amount = bound(amount, 1, type(uint96).max).toUint96();
        // Take uint128 max value as the upper limit because TickMath.MAX_PRICE is above it
        priceAtOpening = bound(priceAtOpening, TickMath.MIN_PRICE, type(uint128).max).toUint128();
        currentPrice = bound(currentPrice, priceAtOpening, type(uint128).max).toUint128();
        leverage = bound(leverage, protocol.getMinLeverage(), protocol.getMaxLeverage());

        // Start checks
        uint128 liqPrice =
            priceAtOpening - FixedPointMathLib.fullMulDiv(priceAtOpening, levDecimals, leverage).toUint128();
        uint128 positionExpo = FixedPointMathLib.fullMulDiv(amount, leverage, levDecimals).toUint128();
        uint256 expectedValue = FixedPointMathLib.fullMulDiv(positionExpo, (currentPrice - liqPrice), currentPrice);
        uint256 value = protocol.i_positionValue(currentPrice, liqPrice, positionExpo);
        assertEq(expectedValue, value, "Returned value is incorrect");
    }
}
