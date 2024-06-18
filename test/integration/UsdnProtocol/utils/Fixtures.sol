// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { BaseFixture } from "../../../utils/Fixtures.sol";
import {
    DEPLOYER,
    ADMIN,
    SDEX,
    WSTETH,
    PYTH_ETH_USD,
    PYTH_ORACLE,
    REDSTONE_ETH_USD,
    CHAINLINK_ORACLE_ETH,
    CHAINLINK_ORACLE_GAS
} from "../../../utils/Constants.sol";
import {
    PYTH_DATA_ETH_PRICE,
    PYTH_DATA_ETH_CONF,
    PYTH_DATA_TIMESTAMP,
    PYTH_DATA_ETH
} from "../../Middlewares/utils/Constants.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { MockPyth } from "../../../unit/Middlewares/utils/MockPyth.sol";
import { MOCK_PYTH_DATA } from "../../../unit/Middlewares/utils/Constants.sol";

import { MockChainlinkOnChain } from "../../../unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { UsdnProtocolHandler } from "../../../unit/UsdnProtocol/utils/Handler.sol";

import { LiquidationRewardsManager } from "../../../../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import {
    ProtocolAction,
    PreviousActionsData,
    PositionId,
    TickData
} from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { WstEthOracleMiddleware } from "../../../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { Permit2TokenBitfield } from "../../../../src/libraries/Permit2TokenBitfield.sol";

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

    struct ExpoImbalanceLimitsBps {
        int256 depositExpoImbalanceLimitBps;
        int256 withdrawalExpoImbalanceLimitBps;
        int256 openExpoImbalanceLimitBps;
        int256 closeExpoImbalanceLimitBps;
        int256 longImbalanceTargetBps;
    }

    Permit2TokenBitfield.Bitfield constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);

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

    ExpoImbalanceLimitsBps internal defaultLimits;

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
                address(pyth), PYTH_ETH_USD, REDSTONE_ETH_USD, address(chainlinkOnChain), address(wstETH), 1 hours
            );
            PriceInfo memory currentPrice =
                oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.Initialize, "");
            testParams.initialLiqPrice = uint128(currentPrice.neutralPrice) / 2;
            AggregatorV3Interface chainlinkGasPriceFeed = AggregatorV3Interface(CHAINLINK_ORACLE_GAS);
            liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);
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
                address(mockPyth),
                PYTH_ETH_USD,
                REDSTONE_ETH_USD,
                address(mockChainlinkOnChain),
                address(wstETH),
                1 hours
            );
            vm.warp(testParams.initialTimestamp);
            liquidationRewardsManager =
                new LiquidationRewardsManager(address(new MockChainlinkOnChain()), wstETH, 2 days);
        }
        vm.startPrank(DEPLOYER);
        (bool success,) = address(wstETH).call{ value: DEPLOYER.balance * 9 / 10 }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));

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

    function _setUpImbalanced()
        internal
        returns (
            int24 tickSpacing_,
            uint128 amountInRebalancer_,
            PositionId memory posToLiquidate_,
            TickData memory tickToLiquidateData_
        )
    {
        params = DEFAULT_PARAMS;
        params.initialDeposit += 100 ether;
        params.initialLong += 100 ether;
        _setUp(params);

        sdex.mintAndApprove(address(this), 50_000 ether, address(protocol), type(uint256).max);

        tickSpacing_ = protocol.getTickSpacing();

        vm.startPrank(DEPLOYER);
        protocol.setFundingSF(0);
        protocol.resetEMA();

        defaultLimits = ExpoImbalanceLimitsBps({
            depositExpoImbalanceLimitBps: protocol.getDepositExpoImbalanceLimitBps(),
            withdrawalExpoImbalanceLimitBps: protocol.getWithdrawalExpoImbalanceLimitBps(),
            openExpoImbalanceLimitBps: protocol.getOpenExpoImbalanceLimitBps(),
            closeExpoImbalanceLimitBps: protocol.getCloseExpoImbalanceLimitBps(),
            longImbalanceTargetBps: protocol.getLongImbalanceTargetBps()
        });

        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0);

        vm.stopPrank();

        // mint wstEth to the test contract
        (bool success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        wstETH.approve(address(rebalancer), type(uint256).max);

        uint256 messageValue = protocol.getSecurityDepositValue();

        uint128 amount = 3 ether;

        // deposit assets in the rebalancer
        rebalancer.depositAssets(amount, payable(address(this)));
        amountInRebalancer_ += amount;

        // deposit assets in the protocol to imbalance it
        protocol.initiateDeposit{ value: messageValue }(
            30 ether, payable(address(this)), payable(address(this)), NO_PERMIT2, "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        mockPyth.setPrice(2000e8);
        mockPyth.setLastPublishTime(block.timestamp);

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);

        protocol.validateDeposit{ value: oracleFee }(payable(address(this)), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        // open a position to liquidate and trigger the rebalancer
        (, posToLiquidate_) = protocol.initiateOpenPosition{ value: messageValue }(
            10 ether, 1500 ether, payable(address(this)), payable(address(this)), NO_PERMIT2, "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        mockPyth.setPrice(2000e8);
        mockPyth.setLastPublishTime(block.timestamp);

        oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: oracleFee }(payable(address(this)), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        tickToLiquidateData_ = protocol.getTickData(posToLiquidate_.tick);

        vm.prank(DEPLOYER);
        protocol.setExpoImbalanceLimits(
            uint256(defaultLimits.depositExpoImbalanceLimitBps),
            uint256(defaultLimits.withdrawalExpoImbalanceLimitBps),
            uint256(defaultLimits.openExpoImbalanceLimitBps),
            uint256(defaultLimits.closeExpoImbalanceLimitBps),
            defaultLimits.longImbalanceTargetBps
        );
    }
}
