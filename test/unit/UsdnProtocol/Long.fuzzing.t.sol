// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

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
     * @custom:given An amount between 1 wei and type(uint128).max ether
     * @custom:and an opening price between the protocol's min price and type(uint128).max
     * @custom:and a current price between the opening price and type(uint128).max
     * @custom:and a leverage between the protocol's min and max values
     * @custom:when _positionValue is called
     * @custom:then The returned value is equal to the expected value.
     * @param amount The amount used as collateral
     * @param priceAtOpening The price of the asset when the position was opened
     * @param currentPrice The price of the asset now
     * @param leverage The leverage of the position
     */
    function testFuzz_positionValue(uint128 amount, uint128 priceAtOpening, uint128 currentPrice, uint256 leverage)
        public
    {
        uint256 levDecimals = 10 ** protocol.LEVERAGE_DECIMALS();
        uint256 maxLeverage = protocol.getMaxLeverage();

        // Set some boundaries for the fuzzed inputs
        amount = bound(amount, 1, type(uint128).max * levDecimals / maxLeverage).toUint128();
        // Take uint128 max value as the upper limit because TickMath.MAX_PRICE is above it
        priceAtOpening = bound(priceAtOpening, TickMath.MIN_PRICE, type(uint128).max).toUint128();
        currentPrice = bound(currentPrice, priceAtOpening, type(uint128).max).toUint128();
        leverage = bound(leverage, protocol.getMinLeverage(), maxLeverage);

        // Start checks
        uint128 liqPrice = protocol.i_getLiquidationPrice(priceAtOpening, uint128(leverage));
        uint128 positionTotalExpo = FixedPointMathLib.fullMulDiv(amount, leverage, levDecimals).toUint128();
        uint256 expectedValue = FixedPointMathLib.fullMulDiv(positionTotalExpo, (currentPrice - liqPrice), currentPrice);
        uint256 value = protocol.i_positionValue(currentPrice, liqPrice, positionTotalExpo);
        assertEq(expectedValue, value, "Returned value is incorrect");
    }

    /**
     * @custom:scenario Compare the implementation of `_positionValue` with leverage vs with expo
     * @custom:given An amount between 1 wei and type(uint128).max ether
     * @custom:and an opening price between the protocol's min price and type(uint128).max
     * @custom:and a current price between the opening price and type(uint128).max
     * @custom:and a leverage between the protocol's min and max values
     * @custom:when _positionValue is called
     * @custom:and the result is compared to the calculation with the leverage
     * @custom:then The difference is within the tolerated values.
     * @param amount The amount used as collateral
     * @param priceAtOpening The price of the asset when the position was opened
     * @param currentPrice The price of the asset now
     * @param leverage The leverage of the position
     */
    function testFuzz_comparePositionValueCalculationWithExpoVSWithLeverage(
        uint128 amount,
        uint128 priceAtOpening,
        uint128 currentPrice,
        uint256 leverage
    ) public {
        uint256 levDecimals = 10 ** protocol.LEVERAGE_DECIMALS();
        uint256 maxLeverage = protocol.getMaxLeverage();

        // Set some boundaries for the fuzzed inputs
        amount = bound(amount, 1, type(uint128).max * levDecimals / maxLeverage).toUint128();
        // Take uint128 max value as the upper limit because TickMath.MAX_PRICE is above it
        priceAtOpening = bound(priceAtOpening, TickMath.MIN_PRICE, type(uint128).max).toUint128();
        currentPrice = bound(currentPrice, priceAtOpening, type(uint128).max).toUint128();
        leverage = bound(leverage, protocol.getMinLeverage(), maxLeverage);

        // Start checks
        uint128 liqPrice = protocol.i_getLiquidationPrice(priceAtOpening, uint128(leverage));
        uint128 positionTotalExpo = FixedPointMathLib.fullMulDiv(amount, leverage, levDecimals).toUint128();

        // Current implementation of position value's calculation
        uint256 posValueWithExpo = protocol.i_positionValue(currentPrice, liqPrice, positionTotalExpo);
        // Previous implementation of position value's calculation
        uint256 posValueWithLeverage =
            FixedPointMathLib.fullMulDiv(amount, leverage * (currentPrice - liqPrice), currentPrice * levDecimals);

        assertApproxEqAbs(
            posValueWithExpo,
            posValueWithLeverage,
            1,
            "Difference between current and former implementations is above tolerance"
        );
    }

    /**
     * @custom:scenario Compare calculations of `_calculatePositionTotalExpo` with more precise values
     */
    function testFuzzFFI_calculatePositionTotalExpo(uint256 amount, uint256 startPrice, uint256 liqPrice) public {
        uint256 levDecimals = 10 ** protocol.LEVERAGE_DECIMALS();
        amount = bound(amount, 1, (type(uint128).max * levDecimals / protocol.getMaxLeverage()) / 2);
        startPrice = bound(startPrice, TickMath.MIN_PRICE, type(uint128).max);
        uint256 minLiqrice = startPrice - (startPrice * levDecimals / protocol.getMinLeverage());
        uint256 maxLiqrice = startPrice - (startPrice * levDecimals / protocol.getMaxLeverage());
        liqPrice = bound(liqPrice, minLiqrice, maxLiqrice);

        string[] memory cmds = new string[](5);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "calc-expo";
        cmds[2] = vm.toString(startPrice);
        cmds[3] = vm.toString(liqPrice);
        cmds[4] = vm.toString(amount);
        bytes memory result = vm.ffi(cmds);

        // Sanity check
        require(keccak256(result) != keccak256(""), "Rust implementation returned an error");

        uint256 positionTotalExpoRust = abi.decode(result, (uint256));
        uint256 positionTotalExpoSol =
            protocol.i_calculatePositionTotalExpo(uint128(amount), uint128(startPrice), uint128(liqPrice));
        assertEq(
            positionTotalExpoSol,
            positionTotalExpoRust,
            "The rust and solidity implementations should return the same value"
        );
    }
}
