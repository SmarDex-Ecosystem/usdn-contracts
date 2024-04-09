// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";

/**
 * @custom:feature Fuzzing tests for the _calcPositionAmount function in the long part of the protocol
 * @custom:background Given an initialized protocol instance
 */
contract TestUsdnProtocolLongCalcPositionAmount is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call `_calcPositionAmount` reverts when the liquidation price is greater than
     * the start price.
     * @custom:given A liquidation price greater than or equal to the start price
     * @custom:when _calcPositionAmount is called
     * @custom:then The transaction reverts with a UsdnProtocolInvalidLiquidationPrice error
     */
    function test_RevertWhen_calcPositionAmountWithLiqPriceGreaterThanStartPrice() public {
        uint128 startPrice = 2000 ether;
        uint128 liqPrice = 2000 ether;

        /* ------------------------- startPrice == liqPrice ------------------------- */
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liqPrice, startPrice));
        protocol.i_calcPositionAmount(1 ether, startPrice, liqPrice);

        /* -------------------------- liqPrice > startPrice ------------------------- */
        liqPrice = startPrice + 1;
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liqPrice, startPrice));
        protocol.i_calcPositionAmount(1 ether, startPrice, liqPrice);
    }

    /**
     * @custom:scenario Check calculations of `_calcPositionAmount`
     * @custom:given A total expo between (maxLeverage / levDecimals) wei and type(uint128).max ether
     * @custom:and an opening price between the protocol's min price and type(uint128).max
     * @custom:and a leverage between the protocol's min and max values
     * @custom:when _calcPositionAmount is called
     * @custom:then The returned amount is approximately equal to the expected value.
     * @param totalExpo The total expo of the position
     * @param startPrice The price of the asset when the position was opened
     * @param leverage The leverage of the position
     */
    function testFuzz_calcPositionAmount(uint128 totalExpo, uint128 startPrice, uint256 leverage) public {
        uint256 levDecimals = 10 ** protocol.LEVERAGE_DECIMALS();
        uint128 maxLeverage = protocol.getMaxLeverage().toUint128();

        // Set some boundaries for the fuzzed inputs
        uint128 boundedLeverage = bound(leverage, protocol.getMinLeverage(), maxLeverage).toUint128();
        totalExpo = bound(totalExpo, maxLeverage / levDecimals, type(uint128).max).toUint128();
        startPrice = bound(startPrice, TickMath.MIN_PRICE, type(uint128).max).toUint128();
        uint128 liqPrice = protocol.i_getLiquidationPrice(startPrice, boundedLeverage);

        // Start checks
        uint128 expectedAmount = FixedPointMathLib.fullMulDiv(totalExpo, startPrice - liqPrice, startPrice).toUint128();
        uint128 amount = protocol.i_calcPositionAmount(totalExpo, startPrice, liqPrice);
        assertEq(expectedAmount, amount, "Returned amount is incorrect");

        // Check that we get the same total expo by doing the calculation the other way around (1 decimal approx)
        uint128 calculatedTotalExpo = protocol.i_calculatePositionTotalExpo(amount, startPrice, liqPrice);
        assertApproxEqAbs(
            calculatedTotalExpo,
            totalExpo,
            10,
            "The difference between the total expo from the calculated amount and the calculated total expo is too high"
        );

        if (calculatedTotalExpo != totalExpo) {
            assertLt(
                calculatedTotalExpo, totalExpo, "If both total expo differs, the calculatedTotalExpo should be lower"
            );
        }
    }
}
