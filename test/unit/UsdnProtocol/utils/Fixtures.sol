// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { IUsdnProtocolErrors, IUsdnProtocolEvents, Position } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
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
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        protocol = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 100); // tick spacing 100 = 1%
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize(
            10 ether, 10 ether, protocol.getEffectiveTickForPrice(1000 ether), abi.encode(uint128(2000 ether))
        );
        vm.stopPrank();
    }

    function test_setUp() public {
        assertGt(protocol.tickSpacing(), 1, "tickSpacing"); // we want to test all functions for a tickSpacing > 1
        assertEq(wstETH.balanceOf(address(protocol)), 20 ether, "wstETH protocol balance");
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "usdn dead address balance");
        assertEq(usdn.balanceOf(DEPLOYER), 20_000 ether - protocol.MIN_USDN_SUPPLY(), "usdn deployer balance");
        assertEq(usdn.totalSupply(), 20_000 ether, "usdn total supply");
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0);
        assertEq(defaultPos.leverage, 1_000_000_000, "default pos leverage");
        assertEq(defaultPos.timestamp, block.timestamp, "default pos timestamp");
        assertEq(defaultPos.user, protocol.DEAD_ADDRESS(), "default pos user");
        assertEq(defaultPos.amount, protocol.FIRST_LONG_AMOUNT(), "default pos amount");
        assertEq(defaultPos.startPrice, 2000 ether, "default pos start price");
        Position memory firstPos = protocol.getLongPosition(protocol.getEffectiveTickForPrice(1000 ether), 0);
        assertEq(firstPos.leverage, 1_983_994_053, "first pos leverage");
        assertEq(firstPos.timestamp, block.timestamp, "first pos timestamp");
        assertEq(firstPos.user, DEPLOYER, "first pos user");
        assertEq(firstPos.amount, 10 ether - protocol.FIRST_LONG_AMOUNT(), "first pos amount");
        assertEq(firstPos.startPrice, 2000 ether, "first pos start price");
    }
}
