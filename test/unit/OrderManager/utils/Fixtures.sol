// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { OrderManagerHandler } from "test/unit/OrderManager/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { Sdex } from "test/utils/Sdex.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";
import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerTypes } from "src/interfaces/OrderManager/IOrderManagerTypes.sol";
import {
    Position,
    PendingAction,
    ProtocolAction,
    PreviousActionsData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { Usdn } from "src/Usdn.sol";

/**
 * @title OrderManagerFixture
 * @dev Utils for testing the order manager
 */
contract OrderManagerFixture is BaseFixture, IOrderManagerTypes, IOrderManagerErrors, IOrderManagerEvents {
    Usdn public usdn;
    Sdex public sdex;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    MockChainlinkOnChain public chainlinkGasPriceFeed;
    LiquidationRewardsManager public liquidationRewardsManager;
    OrderManagerHandler public orderManager;
    UsdnProtocol public protocol;
    uint256 public usdnInitialTotalSupply;
    address[] public users;

    PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    modifier prankUser(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function _setUp() public virtual {
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        sdex = new Sdex();
        oracleMiddleware = new MockOracleMiddleware();
        chainlinkGasPriceFeed = new MockChainlinkOnChain();
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);

        protocol = new UsdnProtocol(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN // Fee collector
        );
        orderManager = new OrderManagerHandler(protocol);

        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);

        // separate the roles ADMIN and DEPLOYER
        protocol.transferOwnership(ADMIN);
        vm.stopPrank();

        usdnInitialTotalSupply = usdn.totalSupply();
    }
}
