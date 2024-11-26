// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { TickMath } from "../../../../src/libraries/TickMath.sol";

/**
 * @custom:feature The `_calcPositionTotalExpo` internal function of the UsdnProtocolLong contract
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongCalcPositionTotalExpo is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Compare calculations of `_calcPositionTotalExpo` with more precise values
     * @custom:when The function `_calcPositionTotalExpo` is called with some parameters
     * @custom:then The result is equal to the result of the Rust implementation
     */
    function testFuzzFFI_calcPositionTotalExpo(uint128 amount, uint256 startPrice, uint256 liqPrice) public {
        uint256 levDecimals = 10 ** Constants.LEVERAGE_DECIMALS;
        amount = bound(amount, 1, type(uint128).max * levDecimals / protocol.getMaxLeverage()).toUint128();
        startPrice = bound(startPrice, TickMath.MIN_PRICE, type(uint128).max);
        uint256 minLiqrice = startPrice - (startPrice * levDecimals / protocol.getMinLeverage());
        uint256 maxLiqrice = startPrice - (startPrice * levDecimals / protocol.getMaxLeverage());
        liqPrice = bound(liqPrice, minLiqrice, maxLiqrice);

        bytes memory result =
            vmFFIRustCommand("calc-expo", vm.toString(startPrice), vm.toString(liqPrice), vm.toString(amount));

        // Sanity check
        require(keccak256(result) != keccak256(""), "Rust implementation returned an error");

        uint256 positionTotalExpoRust = abi.decode(result, (uint256));
        uint256 positionTotalExpoSol = protocol.i_calcPositionTotalExpo(amount, uint128(startPrice), uint128(liqPrice));
        assertEq(
            positionTotalExpoSol,
            positionTotalExpoRust,
            "The rust and solidity implementations should return the same value"
        );
    }

    /**
     * @custom:scenario Call `_calcPositionTotalExpo` reverts when the liquidation price is greater than
     * the start price.
     * @custom:given A liquidation price greater than or equal to the start price
     * @custom:when `_calcPositionTotalExpo` is called
     * @custom:then The transaction reverts with a `UsdnProtocolInvalidLiquidationPrice` error
     */
    function test_RevertWhen_calcPositionTotalExpoWithLiqPriceGreaterThanStartPrice() public {
        uint128 startPrice = 2000 ether;
        uint128 liqPrice = 2000 ether;

        /* ------------------------- startPrice == liqPrice ------------------------- */
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liqPrice, startPrice));
        protocol.i_calcPositionTotalExpo(1 ether, startPrice, liqPrice);

        /* -------------------------- liqPrice > startPrice ------------------------- */
        liqPrice = 2000 ether + 1;
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liqPrice, startPrice));
        protocol.i_calcPositionTotalExpo(1 ether, startPrice, liqPrice);
    }

    /**
     * @custom:scenario Check calculations of `_calcPositionTotalExpo`
     * @custom:given An amount, a startPrice and a liquidationPrice
     * @custom:when The function `_calcPositionTotalExpo` is called with some parameters
     * @custom:then Expo is calculated correctly
     */
    function test_calcPositionTotalExpo() public view {
        uint256 expo = protocol.i_calcPositionTotalExpo(1 ether, 2000 ether, 1500 ether);
        assertEq(expo, 4 ether, "Position total expo should be 4 ether");

        expo = protocol.i_calcPositionTotalExpo(2 ether, 4000 ether, 1350 ether);
        assertEq(expo, 3_018_867_924_528_301_886, "Position total expo should be 3.018... ether");

        expo = protocol.i_calcPositionTotalExpo(1 ether, 2000 ether, 1000 ether);
        assertEq(expo, 2 ether, "Position total expo should be 2 ether");
    }
}
