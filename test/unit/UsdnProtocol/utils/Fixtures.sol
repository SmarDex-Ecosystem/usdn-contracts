// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { IUsdnProtocolErrors, IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { Usdn } from "src/Usdn.sol";

/**
 * @title UsdnProtocolVaultFixture
 * @dev Utils for testing the vault portion of the USDN Protocol
 */
contract UsdnProtocolVaultFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    Usdn public usdn;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    UsdnProtocolHandler public vault;

    function setUp() public virtual {
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        vault = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 10);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
