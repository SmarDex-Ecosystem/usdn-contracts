// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The _getLeverage internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongGetLeverage is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call the `_getLeverage` function
     * @custom:given StartPrice equal to 100 and liquidationPrice equal to 100
     * @custom:when The function is called
     * @custom:then The transaction reverts with the `UsdnProtocolInvalidLiquidationPrice` error
     */
    function test_RevertWhen_getLeverage() public {
        uint128 startPrice = 100;
        uint128 liquidationPrice = 100;
        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolInvalidLiquidationPrice.selector, liquidationPrice, startPrice)
        );
        protocol.i_getLeverage(startPrice, liquidationPrice);
    }

    /**
     * @custom:scenario GetLeverage returns the correct value
     * @custom:given StartPrice equal to 101 and liquidationPrice equal to 100
     * @custom:when The function is called
     * @custom:then The transaction successfully completes
     * @custom:and The leverage is calculated correctly
     */
    function test_getLeverageWithExpectedValue() public {
        uint128 startPrice = 101;
        uint128 liquidationPrice = 100;
        uint128 leverage = protocol.i_getLeverage(startPrice, liquidationPrice);
        assertEq(leverage, 101e21, "Leverage is incorrect");
    }
}
