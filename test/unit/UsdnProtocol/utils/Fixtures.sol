// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/utils/Constants.sol";
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
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialPrice;
        uint256 initialTimestamp;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 10 ether,
        initialLong: 5 ether,
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400 // 2024-01-01 07:00:00 UTC
     });

    Usdn public usdn;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    UsdnProtocolHandler public protocol;
    uint256 public usdnInitialTotalSupply;

    function _setUp(SetUpParams memory testParams) public virtual {
        vm.warp(testParams.initialTimestamp);
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        protocol = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 100); // tick spacing 100 = 1%
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize(
            testParams.initialDeposit,
            testParams.initialLong,
            protocol.getEffectiveTickForPrice(testParams.initialPrice / 2),
            abi.encode(testParams.initialPrice)
        );
        usdnInitialTotalSupply = usdn.totalSupply();
        vm.stopPrank();
        params = testParams;
    }

    function test_setUp() public {
        _setUp(DEFAULT_PARAMS);
        assertGt(protocol.tickSpacing(), 1, "tickSpacing"); // we want to test all functions for a tickSpacing > 1
        assertEq(
            wstETH.balanceOf(address(protocol)), params.initialDeposit + params.initialLong, "wstETH protocol balance"
        );
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "usdn dead address balance");
        uint256 usdnTotalSupply = uint256(params.initialDeposit) * params.initialPrice / 10 ** 18;
        assertEq(usdnTotalSupply, usdnInitialTotalSupply, "usdn total supply");
        assertEq(usdn.balanceOf(DEPLOYER), usdnTotalSupply - protocol.MIN_USDN_SUPPLY(), "usdn deployer balance");
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0);
        assertEq(defaultPos.leverage, 1 gwei, "default pos leverage");
        assertEq(defaultPos.timestamp, block.timestamp, "default pos timestamp");
        assertEq(defaultPos.user, protocol.DEAD_ADDRESS(), "default pos user");
        assertEq(defaultPos.amount, protocol.FIRST_LONG_AMOUNT(), "default pos amount");
        assertEq(defaultPos.startPrice, params.initialPrice, "default pos start price");
        Position memory firstPos =
            protocol.getLongPosition(protocol.getEffectiveTickForPrice(params.initialPrice / 2), 0);
        assertEq(firstPos.leverage, 1_983_994_053, "first pos leverage");
        assertEq(firstPos.timestamp, block.timestamp, "first pos timestamp");
        assertEq(firstPos.user, DEPLOYER, "first pos user");
        assertEq(firstPos.amount, params.initialLong - protocol.FIRST_LONG_AMOUNT(), "first pos amount");
        assertEq(firstPos.startPrice, params.initialPrice, "first pos start price");
    }
}
