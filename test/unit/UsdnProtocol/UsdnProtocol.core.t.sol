// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Core functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 */
contract TestUsdnProtocolCore is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check return values of the `funding` function
     * @custom:when The timestamp is the same as the initial timestamp
     * @custom:then The funding should be 0
     */
    function test_funding() public {
        (int256 fund, int256 longExpo, int256 vaultExpo) =
            protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp));
        assertEq(fund, 0, "fundig should be 0 if no time has passed");
        assertEq(longExpo, 4.919970264999999016 ether, "longExpo if no time has passed");
        assertEq(vaultExpo, 10 ether, "vaultExpo if no time has passed");
    }

    /**
     * @custom:scenario Callling the `funding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_funding_pastTimesptamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp) - 1);
    }
}
