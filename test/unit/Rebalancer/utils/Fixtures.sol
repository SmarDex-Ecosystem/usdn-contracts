// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { RebalancerHandler } from "test/unit/Rebalancer/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { Sdex } from "test/utils/Sdex.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { IRebalancerEvents } from "src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerErrors } from "src/interfaces/Rebalancer/IRebalancerErrors.sol";
import { IRebalancerTypes } from "src/interfaces/Rebalancer/IRebalancerTypes.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { Usdn } from "src/Usdn/Usdn.sol";

/**
 * @title RebalancerFixture
 * @dev Utils for testing the rebalancer
 */
contract RebalancerFixture is BaseFixture, IRebalancerTypes, IRebalancerErrors, IRebalancerEvents {
    Usdn public usdn;
    Sdex public sdex;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    MockChainlinkOnChain public chainlinkGasPriceFeed;
    LiquidationRewardsManager public liquidationRewardsManager;
    RebalancerHandler public rebalancer;
    UsdnProtocol public usdnProtocol;

    function _setUp() public virtual {
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        sdex = new Sdex();
        oracleMiddleware = new MockOracleMiddleware();
        chainlinkGasPriceFeed = new MockChainlinkOnChain();
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);

        usdnProtocol = new UsdnProtocol(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN // Fee collector
        );
        rebalancer = new RebalancerHandler(usdnProtocol);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));

        // separate the roles ADMIN and DEPLOYER
        usdnProtocol.transferOwnership(ADMIN);
        rebalancer.transferOwnership(ADMIN);
        vm.stopPrank();
    }
}
