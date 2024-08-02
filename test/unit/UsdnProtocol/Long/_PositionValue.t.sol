// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The _positionValue internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongPositionValue is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check calculations of `_positionValue`
     * @custom:given A position for 1 wstETH with a starting price of $1000
     * @custom:and a leverage of 2x (liquidation price $500)
     * @custom:or a leverage of 4x (liquidation price $750)
     * @custom:when The current price is $2000 and the leverage is 2x
     * @custom:then The position value is 1.5 wstETH
     * @custom:when the current price is $1000 and the leverage is 2x
     * @custom:then the position value is 1 wstETH
     * @custom:when the current price is $500 and the leverage is 2x
     * @custom:then the position value is 0 wstETH
     * @custom:when the current price is $200 and the leverage is 2x
     * @custom:then the position value is -3 wstETH
     * @custom:when the current price is $2000 and the leverage is 4x
     * @custom:then the position value is 2.5 wstETH
     */
    function test_positionValue() public view {
        uint128 positionTotalExpo = 2 ether;
        int256 value = protocol.i_positionValue(2000 ether, 500 ether, positionTotalExpo);
        assertEq(value, 1.5 ether, "Position value should be 1.5 ether");

        value = protocol.i_positionValue(1000 ether, 500 ether, positionTotalExpo);
        assertEq(value, 1 ether, "Position value should be 1 ether");

        value = protocol.i_positionValue(500 ether, 500 ether, positionTotalExpo);
        assertEq(value, 0 ether, "Position value should be 0");

        value = protocol.i_positionValue(200 ether, 500 ether, positionTotalExpo);
        assertEq(value, -3 ether, "Position value should be negative");

        positionTotalExpo = 4 ether;
        value = protocol.i_positionValue(2000 ether, 750 ether, positionTotalExpo);
        assertEq(value, 2.5 ether, "Position with 4x leverage should have a 2.5 ether value");
    }
}
