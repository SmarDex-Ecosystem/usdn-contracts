// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { ADMIN, DEPLOYER } from "../../../utils/Constants.sol";
import { DefaultConfig } from "../../../utils/DefaultConfig.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import { MockOracleMiddleware } from "./MockOracleMiddleware.sol";
import { UsdnHandler } from "./handlers/Usdn.sol";
import { UsdnProtocolHandler } from "./handlers/UsdnProtocolHandler.sol";
import { UsdnProtocolSafeHandler } from "./handlers/UsdnProtocolSafeHandler.sol";

import { LiquidationRewardsManager } from "../../../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddlewareWithPyth } from "../../../../src/OracleMiddleware/WstEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { FeeCollector } from "../../../../src/utils/FeeCollector.sol";

/// @dev This fixture does not deploy the protocol, only the dependencies
contract UsdnProtocolInvariantBaseFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents, DefaultConfig {
    int24 public constant TICK_SPACING = 100;
    uint128 public constant INITIAL_PRICE = 2000 ether;
    uint128 public constant INITIAL_LONG = 200 ether;

    UsdnHandler public usdn;
    Sdex public sdex;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    LiquidationRewardsManager public liquidationRewardsManager;
    UsdnProtocolFallback protocolFallback;
    // Managers managers;

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
            proxyUpgradeManager: ADMIN,
            pauserManager: ADMIN,
            unpauserManager: ADMIN
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
        UsdnProtocolHandler implementation = new UsdnProtocolHandler(wstETH, sdex);
        _setPeripheralContracts(
            WstEthOracleMiddlewareWithPyth(address(oracleMiddleware)),
            liquidationRewardsManager,
            usdn,
            wstETH,
            address(protocolFallback),
            address(0x1111),
            sdex
        );

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation), abi.encodeCall(UsdnProtocolHandler.initializeStorageHandler, (initStorage))
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
        UsdnProtocolSafeHandler implementation = new UsdnProtocolSafeHandler(wstETH, sdex);

        FeeCollector feeCollector = new FeeCollector(); //NOTE: added fuzzing contract into collector's constructor

        _setPeripheralContracts(
            WstEthOracleMiddlewareWithPyth(address(oracleMiddleware)),
            liquidationRewardsManager,
            usdn,
            wstETH,
            address(protocolFallback),
            address(feeCollector),
            sdex
        );

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation), abi.encodeCall(UsdnProtocolHandler.initializeStorageHandler, (initStorage))
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
        // @todo not working
        // protocol.setRebalancer(rebalancer);
        vm.stopPrank();
    }
}
