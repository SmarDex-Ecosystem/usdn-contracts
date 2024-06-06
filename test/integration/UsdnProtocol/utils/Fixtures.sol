// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";
import {
    DEPLOYER,
    ADMIN,
    SDEX,
    WSTETH,
    PYTH_ETH_USD,
    PYTH_ORACLE,
    CHAINLINK_ORACLE_ETH,
    CHAINLINK_ORACLE_GAS
} from "test/utils/Constants.sol";
import {
    PYTH_DATA_ETH_PRICE,
    PYTH_DATA_ETH_CONF,
    PYTH_DATA_TIMESTAMP,
    PYTH_DATA_ETH
} from "test/integration/Middlewares/utils/Constants.sol";
import { WstETH } from "test/utils/WstEth.sol";
import { Sdex } from "test/utils/Sdex.sol";
import { MockPyth } from "test/unit/Middlewares/utils/MockPyth.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { Rebalancer } from "src/Rebalancer/Rebalancer.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { ProtocolAction, PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Usdn } from "src/Usdn/Usdn.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

contract UsdnProtocolBaseIntegrationFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialLiqPrice;
        uint128 initialPrice;
        uint256 initialTimestamp; // ignored if `fork` is true
        bool fork;
        uint256 forkWarp; // warp to this timestamp after forking, before deploying protocol. Zero to disable
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 99.474794733414559008 ether,
        initialLong: 100 ether,
        initialLiqPrice: 1000 ether, // leverage approx 2x, recalculated if forking (to ensure leverage approx 2x)
        initialPrice: 2000 ether, // 2000 USD per wstETH, ignored if forking
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC
        fork: false,
        forkWarp: 0
    });

    Usdn public usdn;
    Sdex public sdex;
    UsdnProtocolHandler public protocol;
    WstETH public wstETH;
    MockPyth public mockPyth;
    MockChainlinkOnChain public mockChainlinkOnChain;
    WstEthOracleMiddleware public oracleMiddleware;
    LiquidationRewardsManager public liquidationRewardsManager;
    Rebalancer public rebalancer;

    PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    function _setUp(SetUpParams memory testParams) public virtual {
        if (testParams.fork) {
            string memory url = vm.rpcUrl("mainnet");
            vm.createSelectFork(url);
            uint256 initBlock = block.number - 1000;
            vm.rollFork(initBlock);
            if (testParams.forkWarp > 0) {
                vm.warp(testParams.forkWarp);
            }
            dealAccounts(); // provide test accounts with ETH again
            wstETH = WstETH(payable(WSTETH));
            sdex = Sdex(SDEX);
            IPyth pyth = IPyth(PYTH_ORACLE);
            AggregatorV3Interface chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_ETH);
            oracleMiddleware = new WstEthOracleMiddleware(
                address(pyth), PYTH_ETH_USD, address(chainlinkOnChain), address(wstETH), 1 hours
            );
            PriceInfo memory currentPrice =
                oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.Initialize, "");
            testParams.initialLiqPrice = uint128(currentPrice.neutralPrice) / 2;
        } else {
            wstETH = new WstETH();
            sdex = new Sdex();
            mockPyth = new MockPyth();
            mockChainlinkOnChain = new MockChainlinkOnChain();
            mockChainlinkOnChain.setLastPublishTime(testParams.initialTimestamp - 10 minutes);
            // this is the stETH/USD oracle, we need to convert the initialPrice
            mockChainlinkOnChain.setLastPrice(
                int256(wstETH.getStETHByWstETH(uint256(testParams.initialPrice / 10 ** (18 - 8))))
            );
            oracleMiddleware = new WstEthOracleMiddleware(
                address(mockPyth), PYTH_ETH_USD, address(mockChainlinkOnChain), address(wstETH), 1 hours
            );
            vm.warp(testParams.initialTimestamp);
        }
        vm.startPrank(DEPLOYER);
        (bool success,) = address(wstETH).call{ value: 1000 ether }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));
        AggregatorV3Interface chainlinkGasPriceFeed = AggregatorV3Interface(CHAINLINK_ORACLE_GAS);
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);
        protocol = new UsdnProtocolHandler(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN
        );

        rebalancer = new Rebalancer(protocol);
        protocol.setRebalancer(rebalancer);

        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize{ value: oracleMiddleware.validationCost("", ProtocolAction.Initialize) }(
            testParams.initialDeposit, testParams.initialLong, testParams.initialLiqPrice, ""
        );
        vm.stopPrank();
        params = testParams;
    }

    function getHermesApiSignature(bytes32 feed, uint256 timestamp)
        internal
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 timestamp_, bytes memory data_)
    {
        bytes memory result = vmFFIRustCommand("pyth-price", vm.toString(feed), vm.toString(timestamp));

        require(keccak256(result) != keccak256(""), "Rust command returned an error");

        return abi.decode(result, (uint256, uint256, uint256, uint256, bytes));
    }

    function getMockedPythSignature() internal pure returns (uint256, uint256, uint256, bytes memory) {
        return (PYTH_DATA_ETH_PRICE, PYTH_DATA_ETH_CONF, PYTH_DATA_TIMESTAMP, PYTH_DATA_ETH);
    }

    function _waitDelay() internal {
        skip(oracleMiddleware.getValidationDelay() + 1);
    }
}
