// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature The _unadjustPrice internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with default values
 * leverage of ~2x
 */
contract TestUsdnProtocolLongUnadjustPrice is UsdnProtocolBaseFixture {
    using HugeUint for HugeUint.Uint512;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Revert when longTradingExpo is equal to zero
     * @custom:given A price of 100$, an asset price of 2000$, a long trading exposure of 0, and an
     * accumulator of 1
     * @custom:when The _unadjustPrice internal function is called
     * @custom:then The function reverts with the UsdnProtocolZeroLongTradingExpo error
     */
    function test_RevertWhen_longTradingExpoEqualToZero() public {
        vm.expectRevert(UsdnProtocolZeroLongTradingExpo.selector);
        protocol.i_unadjustPrice(100 ether, 2000 ether, 0, HugeUint.wrap(1));
    }
}
