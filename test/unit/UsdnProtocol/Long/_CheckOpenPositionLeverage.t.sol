// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The _checkOpenPositionLeverage internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongCheckOpenPositionLeverage is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check _checkOpenPositionLeverage replace userMaxLeverage by protocol's max leverage if it's
     * higher
     * @custom:when User want to open a long position with a leverage of 20x by providing userMaxLeverage of 20x and
     * corresponding adjustedPrice and liqPriceWithoutPenalty
     * @custom:then The userMaxLeverage is replaced by the protocol's max leverage
     * @custom:and The function reverts with the UsdnProtocolLeverageTooHigh error
     */
    function test_userMaxLeverageHigherThanProtocolMaxLeverage() public {
        uint256 userMaxLeverage = protocol.getMaxLeverage() * 2;
        vm.expectRevert(UsdnProtocolLeverageTooHigh.selector);
        protocol.i_checkOpenPositionLeverage(10 ether, 9.5 ether, userMaxLeverage);
    }
}
