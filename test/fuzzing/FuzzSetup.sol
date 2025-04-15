// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { MockChainlinkOnChain } from "../unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { UsdnHandler } from "../unit/USDN/utils/Handler.sol";
import { DefaultConfig } from "../utils/DefaultConfig.sol";
import { Sdex } from "../utils/Sdex.sol";
import { WstETH } from "../utils/WstEth.sol";
import { IUsdnProtocolHandler } from "./mocks/interfaces/IUsdnProtocolHandler.sol";

import { LiquidationRewardsManagerHandler } from "./mocks/LiquidationRewardsManagerHandler.sol";
import { MockPyth } from "./mocks/MockPyth.sol";
import { RebalancerHandler } from "./mocks/RebalancerHandler.sol";
import { FunctionCalls } from "./util/FunctionCalls.sol";
import { FuzzActors } from "./util/FuzzActors.sol";

import { WstEthOracleMiddleware } from "../../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockWstEthOracleMiddleware } from "../../../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { FeeCollector } from "../../../src/utils/FeeCollector.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { SignedMath } from "../../src/libraries/SignedMath.sol";
import { UsdnProtocolHandler } from "./mocks/UsdnProtocolHandler.sol";

/**
 * @notice Setup contract for fuzz testing the USDN protocol
 * @dev Handles deployment, initialization, and configuration of all required protocol components and mocks
 */
contract FuzzSetup is FunctionCalls, DefaultConfig {
    using SignedMath for int256;

    function setup(address deployerContract) internal {
        DEPLOYER = deployerContract;

        deployPeriphery();
        deployPyth();
        deployChainlink();
        deployOracleMiddleware(address(wstETH));
        deployLiquidationRewardsManager(address(wstETH));
        deployProtocol();
        deployRebalancer();
        mintTokens();
        handlePostDeployment();
        initializeUsdnProtocol();
    }

    function deployPeriphery() internal {
        usdn = new UsdnHandler();
        wusdn = new Wusdn(usdn);
        wstETH = new WstETH();
        sdex = new Sdex();
    }

    function deployPyth() internal {
        pyth = new MockPyth();
    }

    function deployChainlink() internal {
        chainlink = new MockChainlinkOnChain();
    }

    function deployOracleMiddleware(address wstETHAddress) internal {
        wstEthOracleMiddleware = new MockWstEthOracleMiddleware(
            address(pyth), PYTH_FEED_ID, address(chainlink), wstETHAddress, CHAINLINK_PRICE_VALIDITY
        );

        setPrice(2111);
    }

    function deployLiquidationRewardsManager(address wstETHAddress) internal {
        liquidationRewardsManager = new LiquidationRewardsManagerHandler(IWstETH(wstETHAddress));
    }

    function deployProtocol() internal {
        feeCollector = new FeeCollector(); //NOTE: added fuzzing contract into collector's constructor
        usdnProtocolFallback = new UsdnProtocolFallback();
        usdnProtocolHandler = new UsdnProtocolHandler();

        UsdnProtocolHandler implementation = new UsdnProtocolHandler();

        _setPeripheralContracts(
            WstEthOracleMiddleware(address(wstEthOracleMiddleware)),
            liquidationRewardsManager,
            usdn,
            wstETH,
            address(usdnProtocolFallback),
            address(feeCollector),
            sdex
        );

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation), abi.encodeCall(UsdnProtocolHandler.initializeStorageHandler, (initStorage))
        );

        usdnProtocol = IUsdnProtocolHandler(address(proxy));

        _assignUsdnRoles(address(this));
        _assignUsdnRoles(ADMIN);
    }

    function deployRebalancer() internal {
        rebalancer = new RebalancerHandler(usdnProtocol);
    }

    function handlePostDeployment() internal {
        usdnProtocol.setRebalancer(rebalancer);
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        usdn.renounceRole(usdn.DEFAULT_ADMIN_ROLE(), DEPLOYER);
    }

    function initializeUsdnProtocol() public {
        setPrice(2222);

        usdnProtocol.setExpoImbalanceLimits(0, 200, 0, 0, 0, 0); // 2% for deposit

        usdnProtocol.setMinLongPosition(2 ether);

        uint128 minInitAmount = uint128(usdnProtocol.getMinLongPosition() * 2);
        uint128 initialDeposit = uint128(
            (10_000 * minInitAmount) //BPS_DIVISOR
                / uint256(usdnProtocol.getDepositExpoImbalanceLimitBps())
        );
        uint128 initialLong = initialDeposit;
        uint128 INITIAL_PRICE = 3000 ether;

        int24 tick = usdnProtocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        uint128 price = usdnProtocol.getEffectivePriceForTick(tick);

        wstETH.approve(address(usdnProtocol), initialDeposit + initialLong);

        usdnProtocol.initialize{ value: 1 }(initialDeposit, initialLong, price, "");

        int24 highestTick = usdnProtocol.getHighestPopulatedTick();
        initialLongPositionPrice = usdnProtocol.getEffectivePriceForTick(highestTick);
        usdnProtocol.setExpoImbalanceLimits(
            uint256(500), uint256(500), uint256(600), uint256(600), uint256(350), int256(400)
        );

        vm.deal(address(usdnProtocol), 30_000 ether);
    }

    function mintTokens() internal {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(usdnProtocol), type(uint256).max);
        for (uint8 i = 0; i < USERS.length; i++) {
            address user = USERS[i];
            vm.prank(user);
            wstETH.mintAndApprove(user, 10_000 ether, address(usdnProtocol), type(uint256).max);
            vm.prank(user);
            sdex.mintAndApprove(user, 10_000 ether, address(usdnProtocol), type(uint256).max);
            vm.prank(user);
            usdn.approve(address(usdnProtocol), type(uint256).max);
            vm.prank(user);
            wstETH.approve(address(0xdead), type(uint256).max);
            vm.prank(user);
            wstETH.approve(address(rebalancer), type(uint256).max);
            vm.prank(user);
            sdex.approve(address(0xdead), type(uint256).max);
            vm.deal(user, 30_000 ether);
        }
    }

    function setPrice(int256 priceUSD) internal {
        setInitialChainlinkPrice(priceUSD);
        setInitialPythPrice();
    }

    function setInitialChainlinkPrice(int256 priceUSD) internal {
        chainlink.setLastPrice(priceUSD * 1e8);
        chainlink.setLastPublishTime(block.timestamp);

        uint80 roundId = 1;
        int256 answer = priceUSD * 1e8; //2k
        uint256 startedAt = block.timestamp;
        uint80 answeredInRound = 1;

        chainlink.setLatestRoundData(roundId, answer, startedAt, answeredInRound);
    }

    function setInitialPythPrice() internal {
        (, int256 ethPrice,,,) = chainlink.latestRoundData();
        pyth.setLastPublishTime(block.timestamp + wstEthOracleMiddleware.getValidationDelay());
        pyth.setPrice(int64(ethPrice));
    }

    function _assignUsdnRoles(address assignee) internal {
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, assignee);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, assignee);
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, assignee);
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, assignee);

        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, assignee);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, assignee);
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, assignee);
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, assignee);
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, assignee);
    }

    fallback() external payable { }
    receive() external payable { }
}
