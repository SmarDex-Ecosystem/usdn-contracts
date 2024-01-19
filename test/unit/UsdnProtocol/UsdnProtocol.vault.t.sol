// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The internal functions of the vault side of the protocol
 * @custom:background Given a protocol instance that was initialized
 */
contract TestUsdnProtocolVault is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }
}
