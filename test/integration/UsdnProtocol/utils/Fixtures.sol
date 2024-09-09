// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { MOCK_PYTH_DATA } from "../../../unit/Middlewares/utils/Constants.sol";
import { MockChainlinkOnChain } from "../../../unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { MockPyth } from "../../../unit/Middlewares/utils/MockPyth.sol";
import { UsdnProtocolHandler } from "../../../unit/UsdnProtocol/utils/Handler.sol";
import {
    ADMIN,
    CHAINLINK_ORACLE_ETH,
    CHAINLINK_ORACLE_GAS,
    CRITICAL_FUNCTIONS_MANAGER,
    DEPLOYER,
    PROXY_UPGRADE_MANAGER,
    PYTH_ETH_USD,
    PYTH_ORACLE,
    SDEX,
    SET_EXTERNAL_MANAGER,
    SET_OPTIONS_MANAGER,
    SET_PROTOCOL_PARAMS_MANAGER,
    SET_USDN_PARAMS_MANAGER,
    WSTETH
} from "../../../utils/Constants.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { IUsdnProtocolHandler } from "../../../utils/IUsdnProtocolHandler.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import {
    PYTH_DATA_ETH,
    PYTH_DATA_ETH_CONF,
    PYTH_DATA_ETH_PRICE,
    PYTH_DATA_TIMESTAMP
} from "../../Middlewares/utils/Constants.sol";

import { LiquidationRewardsManager } from "../../../../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../../../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
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
        bool enableRoles;
    }

    struct ExpoImbalanceLimitsBps {
        int256 depositExpoImbalanceLimitBps;
        int256 withdrawalExpoImbalanceLimitBps;
        int256 openExpoImbalanceLimitBps;
        int256 closeExpoImbalanceLimitBps;
        int256 rebalancerCloseExpoImbalanceLimitBps;
        int256 longImbalanceTargetBps;
    }

    Permit2TokenBitfield.Bitfield constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 0, // 0 = auto-calculate to initialize a balanced protocol
        initialLong: 100 ether,
        initialLiqPrice: 1000 ether, // leverage approx 2x, recalculated if forking (to ensure leverage approx 2x)
        initialPrice: 2000 ether, // 2000 USD per wstETH, ignored if forking
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC
        fork: false,
        forkWarp: 0,
        enableRoles: true
    });

    Managers managers = Managers({
        setExternalManager: SET_EXTERNAL_MANAGER,
        criticalFunctionsManager: CRITICAL_FUNCTIONS_MANAGER,
        setProtocolParamsManager: SET_PROTOCOL_PARAMS_MANAGER,
        setUsdnParamsManager: SET_USDN_PARAMS_MANAGER,
        setOptionsManager: SET_OPTIONS_MANAGER,
        proxyUpgradeManager: PROXY_UPGRADE_MANAGER
    });

    Usdn public usdn;
    Sdex public sdex;
    IUsdnProtocolHandler public protocol;
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
                address(pyth), PYTH_ETH_USD, address(chainlinkOnChain), address(wstETH), 1 hours
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
                int256(wstETH.getWstETHByStETH(uint256(testParams.initialPrice / 10 ** (18 - 8))))
            );
            oracleMiddleware = new WstEthOracleMiddleware(
                address(mockPyth), PYTH_ETH_USD, address(mockChainlinkOnChain), address(wstETH), 1 hours
            );
            vm.warp(testParams.initialTimestamp);
            liquidationRewardsManager =
                new LiquidationRewardsManager(address(new MockChainlinkOnChain()), wstETH, 2 days);
        }
        vm.startPrank(DEPLOYER);
        (bool success,) = address(wstETH).call{ value: DEPLOYER.balance * 9 / 10 }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));

        if (!testParams.enableRoles) {
            managers = Managers({
                setExternalManager: ADMIN,
                criticalFunctionsManager: ADMIN,
                setProtocolParamsManager: ADMIN,
                setUsdnParamsManager: ADMIN,
                setOptionsManager: ADMIN,
                proxyUpgradeManager: ADMIN
            });
        }

        UsdnProtocolHandler implementation = new UsdnProtocolHandler();
        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation),
            abi.encodeCall(
                UsdnProtocolHandler.initializeStorageHandler,
                (
                    usdn,
                    sdex,
                    wstETH,
                    oracleMiddleware,
                    liquidationRewardsManager,
                    100, // tick spacing 100 = ~1.005%
                    ADMIN,
                    managers,
                    protocolFallback
                )
            )
        );
        protocol = IUsdnProtocolHandler(proxy);

        rebalancer = new Rebalancer(protocol);
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);

        if (testParams.initialDeposit == 0) {
            (, uint128 liqPriceWithoutPenalty) = protocol.i_getTickFromDesiredLiqPrice(
                testParams.initialPrice / 2,
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
        vm.prank(managers.setExternalManager);
        protocol.setRebalancer(rebalancer);
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

    function _setUpImbalanced(uint128 additionalLongAmount)
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

        sdex.mintAndApprove(address(this), 50_000 ether, address(protocol), type(uint256).max);

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

        // mint wstEth to the test contract
        (bool success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        wstETH.approve(address(rebalancer), type(uint256).max);

        uint256 messageValue = protocol.getSecurityDepositValue();

        uint88 amount = 3 ether;

        // deposit assets in the rebalancer
        rebalancer.initiateDepositAssets(amount, payable(address(this)));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        amountInRebalancer_ += amount;

        // deposit assets in the protocol to imbalance it
        protocol.initiateDeposit{ value: messageValue }(
            30 ether, 0, payable(address(this)), payable(address(this)), NO_PERMIT2, "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        {
            uint128 wstEthPrice = 2000 ether;
            uint128 ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice));
            mockPyth.setPrice(int64(uint64(ethPrice / 1e10)));
            mockPyth.setLastPublishTime(block.timestamp - 1);
        }

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);

        protocol.validateDeposit{ value: oracleFee }(payable(address(this)), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        // open a position to liquidate and trigger the rebalancer
        (, posToLiquidate_) = protocol.initiateOpenPosition{ value: messageValue }(
            additionalLongAmount,
            1500 ether,
            payable(address(this)),
            payable(address(this)),
            NO_PERMIT2,
            "",
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        mockPyth.setLastPublishTime(block.timestamp);

        oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: oracleFee }(payable(address(this)), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        tickToLiquidateData_ = protocol.getTickData(posToLiquidate_.tick);

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
}
