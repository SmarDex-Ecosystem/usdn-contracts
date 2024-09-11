// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { ADMIN, DEPLOYER } from "../../../utils/Constants.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import { MockChainlinkOnChain } from "../../Middlewares/utils/MockChainlinkOnChain.sol";
import { MockOracleMiddleware } from "../../UsdnProtocol/utils/MockOracleMiddleware.sol";
import { RebalancerHandler } from "../utils/Handler.sol";

import { LiquidationRewardsManager } from "../../../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IRebalancerErrors } from "../../../../src/interfaces/Rebalancer/IRebalancerErrors.sol";
import { IRebalancerEvents } from "../../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerTypes } from "../../../../src/interfaces/Rebalancer/IRebalancerTypes.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
    IUsdnProtocol public usdnProtocol;

    Types.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        Types.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    function _setUp() public virtual {
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        sdex = new Sdex();
        oracleMiddleware = new MockOracleMiddleware();
        chainlinkGasPriceFeed = new MockChainlinkOnChain();
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        UsdnProtocolImpl implementation = new UsdnProtocolImpl();
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation),
            abi.encodeCall(
                UsdnProtocolImpl.initializeStorage,
                (
                    usdn,
                    sdex,
                    wstETH,
                    oracleMiddleware,
                    liquidationRewardsManager,
                    100, // tick spacing 100 = ~1.005%
                    ADMIN, // Fee collector
                    Types.Managers({
                        setExternalManager: ADMIN,
                        criticalFunctionsManager: ADMIN,
                        setProtocolParamsManager: ADMIN,
                        setUsdnParamsManager: ADMIN,
                        setOptionsManager: ADMIN,
                        proxyUpgradeManager: ADMIN
                    }),
                    protocolFallback
                )
            )
        );
        usdnProtocol = IUsdnProtocol(proxy);

        rebalancer = new RebalancerHandler(usdnProtocol);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));

        // separate the roles ADMIN and DEPLOYER
        usdnProtocol.beginDefaultAdminTransfer(ADMIN);
        rebalancer.transferOwnership(ADMIN);
        vm.stopPrank();
        vm.startPrank(ADMIN);
        skip(1);
        usdnProtocol.acceptDefaultAdminTransfer();
        rebalancer.acceptOwnership();
        vm.stopPrank();
    }
}
