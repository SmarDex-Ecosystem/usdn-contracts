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
    UsdnProtocolHandler public protocol;

    function setUp() public virtual {
        vm.warp(1_702_633_533);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        protocol = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 10);
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initialize(10 ether, 10 ether, 2 gwei, abi.encode(uint128(2000 ether)));
    }

    function test_setUp() public {
        assertGt(protocol.tickSpacing(), 1); // we want to test all functions for a tickSpacing > 1
        assertEq(wstETH.balanceOf(address(protocol)), 20 ether);
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY());
        assertEq(usdn.balanceOf(address(this)), 20_000 ether - protocol.MIN_USDN_SUPPLY());
        assertEq(usdn.totalSupply(), 20_000 ether);
        // TODO: check that both long positions exist
    }
}
