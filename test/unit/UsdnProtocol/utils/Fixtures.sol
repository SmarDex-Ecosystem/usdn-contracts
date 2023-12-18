// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { IUsdnProtocolErrors, IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { Usdn } from "src/Usdn.sol";

/**
 * @title UsdnProtocolBaseFixture
 * @dev Utils for testing the USDN Protocol
 */
contract UsdnProtocolBaseFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    Usdn public usdn;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    UsdnProtocolHandler public vault;

    function setUp() public virtual {
        vm.warp(1_702_633_533);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        vault = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 10);
        usdn.grantRole(usdn.MINTER_ROLE(), address(vault));
        wstETH.approve(address(vault), type(uint256).max);
        vault.initialize(10 ether, 1, abi.encode(uint128(2000 ether)));
    }

    function test_setUp() public {
        assertEq(wstETH.balanceOf(address(vault)), 10 ether);
        assertEq(usdn.balanceOf(address(this)), 20_000 ether);
        assertEq(usdn.totalSupply(), 20_000 ether);
    }
}
