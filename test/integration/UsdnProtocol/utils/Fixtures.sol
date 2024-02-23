// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { ADMIN, DEPLOYER, CHAINLINK_ORACLE_GAS } from "test/utils/Constants.sol";
import { WstethIntegrationFixture } from "test/integration/OracleMiddleware/utils/Fixtures.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Usdn } from "src/Usdn.sol";

contract UsdnProtocolBaseIntegrationFixture is WstethIntegrationFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialPrice;
        uint256 initialTimestamp;
        uint256 initialBlock;
        bool fork;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 10 ether,
        initialLong: 5 ether,
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC,
        initialBlock: block.number,
        fork: false
    });

    Usdn public usdn;
    UsdnProtocol public protocol;
    LiquidationRewardsManager public liquidationRewardsManager;

    function _setUp(SetUpParams memory testParams) public virtual {
        if (testParams.fork) {
            string memory url = vm.rpcUrl("mainnet");
            vm.createSelectFork(url);
            dealAccounts(); // provide test accounts with ETH again
        }
        super.setUp();
        vm.warp(testParams.initialTimestamp);
        vm.startPrank(DEPLOYER);
        (bool success,) = address(WST_ETH).call{ value: 1000 ether }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));
        AggregatorV3Interface chainlinkGasPriceFeed = AggregatorV3Interface(CHAINLINK_ORACLE_GAS);
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), WST_ETH, 2 days);
        protocol = new UsdnProtocol(
            usdn,
            WST_ETH,
            wstethMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN
        );

        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        WST_ETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize{ value: wstethMiddleware.getValidationCost("", ProtocolAction.Initialize) }(
            testParams.initialDeposit, testParams.initialLong, testParams.initialPrice / 2, ""
        );
        vm.stopPrank();
        params = testParams;
    }
}
