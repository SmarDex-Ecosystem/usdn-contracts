// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { MOCK_STREAM_V3 } from "../../../unit/Middlewares/utils/Constants.sol";
import { MockChainlinkOnChain } from "../../../unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { MockPyth } from "../../../unit/Middlewares/utils/MockPyth.sol";
import { UsdnProtocolHandler } from "../../../unit/UsdnProtocol/utils/Handler.sol";
import {
    ADMIN,
    CHAINLINK_DATA_STREAMS_WSTETH_USD,
    CHAINLINK_ORACLE_ETH,
    CHAINLINK_VERIFIER_PROXY,
    DEPLOYER,
    PYTH_ETH_USD,
    PYTH_ORACLE,
    SDEX,
    WSTETH
} from "../../../utils/Constants.sol";
import { DefaultConfig } from "../../../utils/DefaultConfig.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { IEventsErrors } from "../../../utils/IEventsErrors.sol";
import { RolesUtils } from "../../../utils/RolesUtils.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import {
    PYTH_DATA_ETH,
    PYTH_DATA_ETH_CONF,
    PYTH_DATA_ETH_PRICE,
    PYTH_DATA_TIMESTAMP
} from "../../Middlewares/utils/Constants.sol";
import { MockFeeManager } from "../../Middlewares/utils/MockFeeManager.sol";
import { MockStreamVerifierProxy } from "../../Middlewares/utils/MockStreamVerifierProxy.sol";
import { MockWETH } from "../../Middlewares/utils/MockWETH.sol";

import { LiquidationRewardsManagerWstEth } from
    "../../../../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";
import { WstEthOracleMiddlewareWithDataStreams } from
    "../../../../src/OracleMiddleware/WstEthOracleMiddlewareWithDataStreams.sol";
import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IVerifierProxy } from "../../../../src/interfaces/OracleMiddleware/IVerifierProxy.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";

contract UsdnProtocolBaseIntegrationFixture is
    BaseFixture,
    RolesUtils,
    IUsdnProtocolErrors,
    IUsdnProtocolEvents,
    IEventsErrors,
    DefaultConfig
{
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialLiqPrice;
        uint128 initialPrice;
        uint256 initialTimestamp; // ignored if `fork` is true
        bool fork;
        uint256 forkWarp; // warp to this timestamp after forking, before deploying protocol. Zero to disable
        uint256 forkBlock;
        bool enableRoles;
        string eip712Version;
    }

    struct ExpoImbalanceLimitsBps {
        int256 depositExpoImbalanceLimitBps;
        int256 withdrawalExpoImbalanceLimitBps;
        int256 openExpoImbalanceLimitBps;
        int256 closeExpoImbalanceLimitBps;
        int256 rebalancerCloseExpoImbalanceLimitBps;
        int256 longImbalanceTargetBps;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 0, // 0 = auto-calculate to initialize a balanced protocol
        initialLong: 100 ether,
        initialLiqPrice: 1000 ether, // leverage approx 2x, recalculated if forking (to ensure leverage approx 2x)
        initialPrice: 2000 ether, // 2000 USD per wstETH, ignored if forking
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC
        fork: false,
        forkWarp: 0,
        forkBlock: 0,
        enableRoles: true,
        eip712Version: "1"
    });

    Usdn public usdn;
    Sdex public sdex;
    UsdnProtocolHandler public protocol;
    UsdnProtocolHandler public implementation;
    UsdnProtocolFallback public protocolFallback;
    WstETH public wstETH;
    MockPyth public mockPyth;
    MockChainlinkOnChain public mockChainlinkOnChain;
    MockFeeManager internal mockFeeManager;
    MockStreamVerifierProxy internal mockStreamVerifierProxy;
    WstEthOracleMiddlewareWithDataStreams public oracleMiddleware;
    LiquidationRewardsManagerWstEth public liquidationRewardsManager;
    Rebalancer public rebalancer;

    IVerifierProxy.ReportV3 internal report;
    address internal wethTargetAddress;
    bytes internal reportData;
    bytes internal payload;
    bytes32[3] internal emptySignature;

    PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    ExpoImbalanceLimitsBps internal defaultLimits;

    struct SetUpImbalancedData {
        bool success;
        uint256 messageValue;
        uint88 amount;
        uint128 wstEthPrice;
        uint128 ethPrice;
        uint256 oracleFee;
    }

    function _setUp(SetUpParams memory testParams) public virtual {
        if (!testParams.enableRoles) {
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

        vm.startPrank(DEPLOYER);
        if (testParams.fork) {
            string memory url = vm.rpcUrl("mainnet");
            vm.createSelectFork(url);
            if (testParams.forkBlock > 0) {
                vm.rollFork(testParams.forkBlock);
            } else {
                vm.rollFork(block.number - 1000);
            }
            if (testParams.forkWarp > 0) {
                vm.warp(testParams.forkWarp);
            }
            dealAccounts(); // provide test accounts with ETH again
            wstETH = WstETH(payable(WSTETH));
            sdex = Sdex(SDEX);
            IPyth pyth = IPyth(PYTH_ORACLE);
            AggregatorV3Interface chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_ETH);

            oracleMiddleware = new WstEthOracleMiddlewareWithDataStreams(
                address(pyth),
                PYTH_ETH_USD,
                address(chainlinkOnChain),
                address(wstETH),
                1 hours,
                CHAINLINK_VERIFIER_PROXY,
                CHAINLINK_DATA_STREAMS_WSTETH_USD
            );
            PriceInfo memory currentPrice =
                oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.Initialize, "");
            testParams.initialPrice = uint128(currentPrice.neutralPrice);
            testParams.initialLiqPrice = uint128(currentPrice.neutralPrice) / 2;
            liquidationRewardsManager = new LiquidationRewardsManagerWstEth(wstETH);
        } else {
            wstETH = new WstETH();
            sdex = new Sdex();
            mockPyth = new MockPyth();
            mockChainlinkOnChain = new MockChainlinkOnChain();
            mockChainlinkOnChain.setLastPublishTime(testParams.initialTimestamp - 10 minutes);
            // this is the stETH/USD oracle, we need to convert the initialPrice
            mockChainlinkOnChain.setLastPrice(
                int256(wstETH.getWstETHByStETH(uint256(testParams.initialPrice / 10 ** (18 - 8))))
            );

            mockFeeManager = new MockFeeManager();
            mockStreamVerifierProxy = new MockStreamVerifierProxy(address(mockFeeManager));

            wethTargetAddress = mockFeeManager.i_nativeAddress();
            bytes memory code = vm.getDeployedCode("MockWETH.sol");
            vm.etch(wethTargetAddress, code);

            report = IVerifierProxy.ReportV3({
                feedId: MOCK_STREAM_V3,
                validFromTimestamp: uint32(testParams.initialTimestamp),
                observationsTimestamp: uint32(testParams.initialTimestamp),
                nativeFee: 0.001 ether,
                linkFee: 0,
                expiresAt: uint32(testParams.initialTimestamp) + 100,
                price: int192(int128(testParams.initialPrice)),
                bid: int192(int128(testParams.initialPrice)) - 1,
                ask: int192(int128(testParams.initialPrice)) + 1
            });

            (reportData, payload) = _encodeReport(report);

            oracleMiddleware = new WstEthOracleMiddlewareWithDataStreams(
                address(mockPyth),
                PYTH_ETH_USD,
                address(mockChainlinkOnChain),
                address(wstETH),
                1 hours,
                address(mockStreamVerifierProxy),
                MOCK_STREAM_V3
            );
            vm.warp(testParams.initialTimestamp);
            liquidationRewardsManager = new LiquidationRewardsManagerWstEth(wstETH);
        }
        (bool success,) = address(wstETH).call{ value: DEPLOYER.balance * 9 / 10 }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));

        implementation = new UsdnProtocolHandler(MAX_SDEX_BURN_RATIO, MAX_MIN_LONG_POSITION);
        protocolFallback = new UsdnProtocolFallback(MAX_SDEX_BURN_RATIO, MAX_MIN_LONG_POSITION);

        _setPeripheralContracts(
            oracleMiddleware, liquidationRewardsManager, usdn, wstETH, address(protocolFallback), ADMIN, sdex
        );

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation), abi.encodeCall(UsdnProtocolHandler.initializeStorageHandler, (initStorage))
        );
        protocol = UsdnProtocolHandler(proxy);

        rebalancer = new Rebalancer(IUsdnProtocol(address(protocol)));
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);

        if (testParams.initialDeposit == 0) {
            (, uint128 liqPriceWithoutPenalty) = protocol.i_getTickFromDesiredLiqPrice(
                testParams.initialLiqPrice,
                testParams.initialPrice,
                0,
                HugeUint.wrap(0),
                protocol.getTickSpacing(),
                protocol.getLiquidationPenalty()
            );
            uint128 positionTotalExpo = protocol.i_calcPositionTotalExpo(
                testParams.initialLong, testParams.initialPrice, liqPriceWithoutPenalty
            );
            testParams.initialDeposit = positionTotalExpo - testParams.initialLong;
        }

        // leverage approx 2x
        protocol.initialize{ value: oracleMiddleware.validationCost("", ProtocolAction.Initialize) }(
            testParams.initialDeposit, testParams.initialLong, testParams.initialLiqPrice, ""
        );
        vm.stopPrank();

        _giveRolesTo(managers, IUsdnProtocol(address(protocol)));

        vm.prank(managers.setExternalManager);
        protocol.setRebalancer(rebalancer);
        params = testParams;
        persistContracts();
    }

    function getHermesApiSignature(bytes32 feed, uint256 timestamp)
        internal
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 timestamp_, bytes memory data_)
    {
        bytes memory result = vmFFIRustCommand("pyth-price", vm.toString(feed), vm.toString(timestamp));

        require(keccak256(result) != keccak256(""), "Rust command returned an error");

        return abi.decode(result, (uint256, uint256, uint256, uint256, bytes));
    }

    function getChainlinkDataStreamsApiSignature(bytes32 stream, uint256 timestamp)
        internal
        returns (bytes memory payload_)
    {
        payload_ = vmFFIRustCommand("chainlink-price", vm.toString(stream), vm.toString(timestamp));
        require(keccak256(payload_) != keccak256(""), "Rust command returned an error");
    }

    function getMockedPythSignature() internal pure returns (uint256, uint256, uint256, bytes memory) {
        return (PYTH_DATA_ETH_PRICE, PYTH_DATA_ETH_CONF, PYTH_DATA_TIMESTAMP, PYTH_DATA_ETH);
    }

    function _encodeReport(IVerifierProxy.ReportV3 memory reportV3)
        internal
        view
        returns (bytes memory reportData_, bytes memory payload_)
    {
        reportData_ = abi.encode(reportV3);
        payload_ = abi.encode(emptySignature, reportData_);
    }

    function _waitDelay() internal {
        skip(oracleMiddleware.getValidationDelay() + 1);
    }

    function _setUpImbalanced(address payable user, uint128 additionalLongAmount)
        internal
        returns (
            int24 tickSpacing_,
            uint88 amountInRebalancer_,
            PositionId memory posToLiquidate_,
            TickData memory tickToLiquidateData_
        )
    {
        params = DEFAULT_PARAMS;
        params.initialLong = 200 ether;
        _setUp(params);

        sdex.mintAndApprove(user, 50_000 ether, address(protocol), type(uint256).max);

        tickSpacing_ = protocol.getTickSpacing();

        vm.startPrank(managers.setProtocolParamsManager);
        protocol.setFundingSF(0);
        protocol.resetEMA();

        defaultLimits = ExpoImbalanceLimitsBps({
            depositExpoImbalanceLimitBps: protocol.getDepositExpoImbalanceLimitBps(),
            withdrawalExpoImbalanceLimitBps: protocol.getWithdrawalExpoImbalanceLimitBps(),
            openExpoImbalanceLimitBps: protocol.getOpenExpoImbalanceLimitBps(),
            closeExpoImbalanceLimitBps: protocol.getCloseExpoImbalanceLimitBps(),
            rebalancerCloseExpoImbalanceLimitBps: protocol.getRebalancerCloseExpoImbalanceLimitBps(),
            longImbalanceTargetBps: protocol.getLongImbalanceTargetBps()
        });

        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        vm.stopPrank();

        vm.deal(user, 10_000 ether);

        vm.startPrank(user);
        SetUpImbalancedData memory data;
        // mint wstEth to the test contract
        (data.success,) = address(wstETH).call{ value: 200 ether }("");
        require(data.success, "wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        wstETH.approve(address(rebalancer), type(uint256).max);

        data.messageValue = protocol.getSecurityDepositValue();

        data.amount = 3 ether;

        // deposit assets in the rebalancer
        rebalancer.initiateDepositAssets(data.amount, user);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        amountInRebalancer_ += data.amount;

        // deposit assets in the protocol to imbalance it
        protocol.initiateDeposit{ value: data.messageValue }(
            30 ether, DISABLE_SHARES_OUT_MIN, user, user, type(uint256).max, "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        _setOraclePrices(2000 ether);

        report.validFromTimestamp = uint32(block.timestamp - 1);
        report.observationsTimestamp = uint32(block.timestamp - 1);
        (, payload) = _encodeReport(report);

        uint256 oracleFee = oracleMiddleware.validationCost(payload, ProtocolAction.ValidateDeposit);

        protocol.validateDeposit{ value: oracleFee }(user, payload, EMPTY_PREVIOUS_DATA);

        // open a position to liquidate and trigger the rebalancer
        (, posToLiquidate_) = protocol.initiateOpenPosition{ value: data.messageValue }(
            additionalLongAmount,
            1500 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            user,
            user,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        mockPyth.setLastPublishTime(block.timestamp);

        report.validFromTimestamp = uint32(block.timestamp - 1);
        report.observationsTimestamp = uint32(block.timestamp - 1);
        (, payload) = _encodeReport(report);

        oracleFee = oracleMiddleware.validationCost(payload, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: oracleFee }(user, payload, EMPTY_PREVIOUS_DATA);

        tickToLiquidateData_ = protocol.getTickData(posToLiquidate_.tick);
        vm.stopPrank();

        vm.prank(managers.setProtocolParamsManager);
        protocol.setExpoImbalanceLimits(
            uint256(defaultLimits.depositExpoImbalanceLimitBps),
            uint256(defaultLimits.withdrawalExpoImbalanceLimitBps),
            uint256(defaultLimits.openExpoImbalanceLimitBps),
            uint256(defaultLimits.closeExpoImbalanceLimitBps),
            uint256(defaultLimits.rebalancerCloseExpoImbalanceLimitBps),
            defaultLimits.longImbalanceTargetBps
        );
    }

    /// @dev Set the provided price and current timestamp in all of the mock oracles
    function _setOraclePrices(uint128 wstEthPrice) internal returns (uint128 wstEthPrice_) {
        uint128 ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice)) / 1e10;
        mockPyth.setPrice(int64(uint64(ethPrice)));
        mockPyth.setLastPublishTime(block.timestamp);
        wstEthPrice_ = uint128(wstETH.getStETHByWstETH(ethPrice * 1e10));
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        mockChainlinkOnChain.setLastPrice(int256(uint256(ethPrice)));

        report.validFromTimestamp = uint32(block.timestamp);
        report.observationsTimestamp = uint32(block.timestamp);
        report.expiresAt = uint32(block.timestamp) + 1 hours;
        report.price = int192(int128(wstEthPrice_));
        report.bid = int192(int128(wstEthPrice_)) - 1;
        report.ask = int192(int128(wstEthPrice_)) + 1;
        (reportData, payload) = _encodeReport(report);
    }

    /// @dev this function aims to persist the contracts when use vm.rollFork in tests
    function persistContracts() internal {
        vm.makePersistent(address(protocol));
        vm.makePersistent(address(implementation));
        vm.makePersistent(address(protocolFallback));
        vm.makePersistent(address(oracleMiddleware));
        vm.makePersistent(address(usdn));
        vm.makePersistent(address(wstETH));
        vm.makePersistent(address(rebalancer));
    }
}
