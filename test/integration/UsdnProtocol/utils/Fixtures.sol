// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";
import {
    DEPLOYER,
    ADMIN,
    WSTETH,
    PYTH_STETH_USD,
    PYTH_ORACLE,
    CHAINLINK_ORACLE_STETH,
    CHAINLINK_ORACLE_GAS
} from "test/utils/Constants.sol";
import { WstETH } from "test/utils/WstEth.sol";
import { MockPyth } from "test/unit/OracleMiddleware/utils/MockPyth.sol";
import { MockChainlinkOnChain } from "test/unit/OracleMiddleware/utils/MockChainlinkOnChain.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Usdn } from "src/Usdn.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";

contract UsdnProtocolBaseIntegrationFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialLiqPrice;
        uint128 initialPrice;
        uint256 initialTimestamp;
        uint256 initialBlock;
        bool fork;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 49.19970269703463156 ether,
        initialLong: 50 ether,
        initialLiqPrice: 1000 ether, // leverage approx 2x
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC,
        initialBlock: block.number,
        fork: false
    });

    Usdn public usdn;
    UsdnProtocolHandler public protocol;
    WstETH public wstETH;
    MockPyth public mockPyth;
    MockChainlinkOnChain public mockChainlinkOnChain;
    WstEthOracleMiddleware public oracleMiddleware;
    LiquidationRewardsManager public liquidationRewardsManager;

    function _setUp(SetUpParams memory testParams) public virtual {
        if (testParams.fork) {
            string memory url = vm.rpcUrl("mainnet");
            vm.createSelectFork(url);
            dealAccounts(); // provide test accounts with ETH again
            wstETH = WstETH(payable(WSTETH));
            IPyth pyth = IPyth(PYTH_ORACLE);
            AggregatorV3Interface chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_STETH);
            oracleMiddleware =
                new WstEthOracleMiddleware(address(pyth), PYTH_STETH_USD, address(chainlinkOnChain), WSTETH, 1 hours);
        } else {
            wstETH = new WstETH();
            mockPyth = new MockPyth();
            mockChainlinkOnChain = new MockChainlinkOnChain();
            mockChainlinkOnChain.setLastPublishTime(testParams.initialTimestamp - 10 minutes);
            mockChainlinkOnChain.setLastPrice(int256(uint256(testParams.initialPrice / 10 ** (18 - 8))));
            oracleMiddleware = new WstEthOracleMiddleware(
                address(mockPyth), PYTH_STETH_USD, address(mockChainlinkOnChain), address(wstETH), 1 hours
            );
        }
        vm.warp(testParams.initialTimestamp);
        vm.startPrank(DEPLOYER);
        (bool success,) = address(wstETH).call{ value: 1000 ether }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));
        AggregatorV3Interface chainlinkGasPriceFeed = AggregatorV3Interface(CHAINLINK_ORACLE_GAS);
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);
        protocol = new UsdnProtocolHandler(
            usdn,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN
        );

        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize{ value: oracleMiddleware.validationCost("", ProtocolAction.Initialize) }(
            testParams.initialDeposit, testParams.initialLong, testParams.initialLiqPrice, ""
        );
        vm.stopPrank();
        params = testParams;
    }

    // temporary: will be moved to a base fixture thanks to #91
    function getHermesApiSignature(bytes32 feed, uint256 timestamp)
        internal
        returns (uint256, uint256, uint256, bytes memory)
    {
        string[] memory cmds = new string[](4);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "pyth-price";
        cmds[2] = vm.toString(feed);
        cmds[3] = vm.toString(timestamp);
        bytes memory result = vm.ffi(cmds);
        return abi.decode(result, (uint256, uint256, uint256, bytes));
    }
}
