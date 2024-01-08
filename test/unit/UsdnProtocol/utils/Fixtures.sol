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
        protocol = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 10);
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize(
            10 ether, 10 ether, protocol.getEffectiveTickForPrice(1000 ether), abi.encode(uint128(2000 ether))
        );
        vm.stopPrank();
    }

    function test_setUp() public {
        assertGt(protocol.tickSpacing(), 1); // we want to test all functions for a tickSpacing > 1
        assertEq(wstETH.balanceOf(address(protocol)), 20 ether);
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY());
        assertEq(usdn.balanceOf(DEPLOYER), 20_000 ether - protocol.MIN_USDN_SUPPLY());
        assertEq(usdn.totalSupply(), 20_000 ether);
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0);
        assertEq(defaultPos.leverage, 1_000_000_000);
        assertEq(defaultPos.timestamp, block.timestamp);
        assertEq(defaultPos.user, protocol.DEAD_ADDRESS());
        assertEq(defaultPos.amount, protocol.FIRST_LONG_AMOUNT());
        assertEq(defaultPos.startPrice, 2000 ether);
        Position memory firstPos = protocol.getLongPosition(protocol.getEffectiveTickForPrice(1000 ether), 0);
        assertEq(firstPos.leverage, 1_997_588_415);
        assertEq(firstPos.timestamp, block.timestamp);
        assertEq(firstPos.user, DEPLOYER);
        assertEq(firstPos.amount, 10 ether - protocol.FIRST_LONG_AMOUNT());
        assertEq(firstPos.startPrice, 2000 ether);
    }
}
