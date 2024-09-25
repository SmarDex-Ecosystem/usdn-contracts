// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { UsdnHandler } from "../../../unit/USDN/utils/Handler.sol";
import { ADMIN, DEPLOYER } from "../../../utils/Constants.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import { MockOracleMiddleware } from "../mock/MockOracleMiddleware.sol";
import { UsdnProtocolHandler, UsdnProtocolSafeHandler } from "./Handlers.sol";

import { LiquidationRewardsManager } from "../../../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/// @dev This fixture does not deploy the protocol, only the dependencies
contract UsdnProtocolInvariantBaseFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    int24 public constant TICK_SPACING = 100;
    uint128 public constant INITIAL_PRICE = 2000 ether;
    uint128 public constant INITIAL_LONG = 200 ether;

    UsdnHandler public usdn;
    Sdex public sdex;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    LiquidationRewardsManager public liquidationRewardsManager;
    UsdnProtocolFallback protocolFallback;
    Managers managers;

    function setUp() public virtual {
        vm.warp(1_727_266_553); // 2024-09-25 12:15:53 UTC

        // deploy contracts
        vm.startPrank(DEPLOYER);
        usdn = new UsdnHandler();
        wstETH = new WstETH();
        sdex = new Sdex();
        oracleMiddleware = new MockOracleMiddleware(INITIAL_PRICE);
        liquidationRewardsManager = new LiquidationRewardsManager(wstETH);
        protocolFallback = new UsdnProtocolFallback();
        vm.stopPrank();

        managers = Managers({
            setExternalManager: ADMIN,
            criticalFunctionsManager: ADMIN,
            setProtocolParamsManager: ADMIN,
            setUsdnParamsManager: ADMIN,
            setOptionsManager: ADMIN,
            proxyUpgradeManager: ADMIN
        });
    }
}

/**
 * @dev This fixture deploy the "unsafe" version of the handler, which can revert for some actions depending on the
 * inputs
 */
contract UsdnProtocolInvariantFixture is UsdnProtocolInvariantBaseFixture {
    Rebalancer public rebalancer;
    UsdnProtocolHandler public protocol;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(DEPLOYER);
        UsdnProtocolHandler handler = new UsdnProtocolHandler();

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(handler),
            abi.encodeCall(
                UsdnProtocolImpl.initializeStorage,
                (
                    usdn,
                    sdex,
                    wstETH,
                    oracleMiddleware,
                    liquidationRewardsManager,
                    TICK_SPACING,
                    ADMIN,
                    managers,
                    protocolFallback
                )
            )
        );
        protocol = UsdnProtocolHandler(proxy);
        rebalancer = new Rebalancer(IUsdnProtocol(address(protocol)));

        // initialize protocol
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        (, uint128 liqPriceWithoutPenalty) = protocol.i_getTickFromDesiredLiqPrice(
            INITIAL_PRICE / 2, INITIAL_PRICE, 0, HugeUint.wrap(0), TICK_SPACING, protocol.getLiquidationPenalty()
        );
        uint128 positionTotalExpo =
            protocol.i_calcPositionTotalExpo(INITIAL_LONG, INITIAL_PRICE, liqPriceWithoutPenalty);
        uint128 initialDeposit = positionTotalExpo - INITIAL_LONG;
        protocol.initialize(initialDeposit, INITIAL_LONG, INITIAL_PRICE / 2, "");

        // transfer ownership
        protocol.beginDefaultAdminTransfer(ADMIN);
        rebalancer.transferOwnership(ADMIN);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        skip(1);
        protocol.acceptDefaultAdminTransfer();
        rebalancer.acceptOwnership();

        // set rebalancer
        protocol.setRebalancer(rebalancer);
        vm.stopPrank();
    }
}

/// @dev This fixture deploy the "safe" version of the handler, which cannot revert in normal operation
contract UsdnProtocolInvariantSafeFixture is UsdnProtocolInvariantBaseFixture {
    Rebalancer public rebalancer;
    UsdnProtocolSafeHandler public protocol;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(DEPLOYER);
        UsdnProtocolSafeHandler handler = new UsdnProtocolSafeHandler();

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(handler),
            abi.encodeCall(
                UsdnProtocolImpl.initializeStorage,
                (
                    usdn,
                    sdex,
                    wstETH,
                    oracleMiddleware,
                    liquidationRewardsManager,
                    TICK_SPACING,
                    ADMIN,
                    managers,
                    protocolFallback
                )
            )
        );
        protocol = UsdnProtocolSafeHandler(proxy);
        rebalancer = new Rebalancer(IUsdnProtocol(address(protocol)));

        // initialize protocol
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        (, uint128 liqPriceWithoutPenalty) = protocol.i_getTickFromDesiredLiqPrice(
            INITIAL_PRICE / 2, INITIAL_PRICE, 0, HugeUint.wrap(0), TICK_SPACING, protocol.getLiquidationPenalty()
        );
        uint128 positionTotalExpo =
            protocol.i_calcPositionTotalExpo(INITIAL_LONG, INITIAL_PRICE, liqPriceWithoutPenalty);
        uint128 initialDeposit = positionTotalExpo - INITIAL_LONG;
        protocol.initialize(initialDeposit, INITIAL_LONG, INITIAL_PRICE / 2, "");

        // transfer ownership
        protocol.beginDefaultAdminTransfer(ADMIN);
        rebalancer.transferOwnership(ADMIN);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        skip(1);
        protocol.acceptDefaultAdminTransfer();
        rebalancer.acceptOwnership();

        // set rebalancer
        protocol.setRebalancer(rebalancer);
        vm.stopPrank();
    }
}
