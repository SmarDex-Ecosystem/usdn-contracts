// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Utils } from "./Utils.s.sol";
import { Options, UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { LiquidationRewardsManager } from "../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { Wusdn } from "../src/Usdn/Wusdn.sol";

import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

import { MockFastGasGwei } from "../src/OracleMiddleware/mock/MockFastGasGwei.sol";
import { MockLiquidationRewardsManager } from "../src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";

import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";

import { MockWstEthOracleMiddleware } from "../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";
import { WstETH as WstETHSepolia } from "../src/utils/sepolia/tokens/WstETH.sol";
import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";

contract Deploy is Script {
    Utils utils;
    address deployerAddress;
    uint256 privateKey;
    address feeCollector;
    ChainId chainId;
    uint256 forkId;

    enum ChainId {
        Mainnet,
        Sepolia,
        Fork
    }

    function run() external {
        utils = new Utils();

        string memory rpcUrl = "http://localhost:8545";
        forkId = vm.createSelectFork(rpcUrl);

        privateKey = vm.promptSecretUint("enter the private key");
        deployerAddress = vm.addr(privateKey);

        string memory prompt = string(
            abi.encodePacked(
                "\ndeployer address: ",
                vm.toString(deployerAddress),
                "\nRPC_URL: ",
                rpcUrl,
                "\nchainID: ",
                vm.toString(block.chainid),
                "\n\nAre you sure you want to deploy? (y/n)"
            )
        );

        string memory confirmation = vm.prompt(prompt);
        if (keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("y"))) {
            // return true;
            _deploy();
        } else if (keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("n"))) {
            revert("deployment cancelled");
        } else {
            revert("invalid input");
        }
    }

    function _deploy()
        internal
        returns (
            WstETH WstETH_,
            Sdex Sdex_,
            WstEthOracleMiddleware WstEthOracleMiddleware_,
            LiquidationRewardsManager LiquidationRewardsManager_,
            Rebalancer Rebalancer_,
            Usdn Usdn_,
            Wusdn Wusdn_,
            IUsdnProtocol UsdnProtocol_
        )
    {
        utils.validateProtocol();

        if (block.chainid == 1) {
            chainId = ChainId.Mainnet;
        } else if (block.chainid == 11_155_111) {
            chainId = ChainId.Sepolia;
        } else {
            chainId = ChainId.Fork;
        }

        _handleEnvVariables();

        bool isProdEnv = chainId != ChainId.Fork;

        (uint256 depositAmount, uint256 longAmount) = _getInitialAmounts();

        vm.startBroadcast(privateKey);

        if (chainId == ChainId.Sepolia) {
            (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripherySepoliaDeployment(depositAmount + longAmount);
        }
        // else {
        //     (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripheryDeployment(depositAmount, longAmount);
        // }

        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware(isProdEnv, address(WstETH_));
        LiquidationRewardsManager_ = _deployLiquidationRewardsManager(isProdEnv, address(WstETH_));

        // deploy the USDN protocol
        UsdnProtocol_ =
            _deployProtocol(Usdn_, Sdex_, WstETH_, WstEthOracleMiddleware_, LiquidationRewardsManager_, chainId);

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the USDN protocol
     * @param usdn The USDN token
     * @param sdex The SDEX token
     * @param wstETH The WstETH token
     * @param wstEthOracleMiddleware The WstETH oracle middleware
     * @param liquidationRewardsManager The liquidation rewards manager
     * @param chain The chain id
     * @return usdnProtocol_ The deployed protocol
     */
    function _deployProtocol(
        Usdn usdn,
        Sdex sdex,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager,
        ChainId chain
    ) internal returns (IUsdnProtocol usdnProtocol_) {
        // clean and build contracts for openzeppelin module
        // utils.cleanAndBuildContracts();

        // we need to allow external library linking for the openzeppelin module
        Options memory opts;
        string memory contractName;
        // we need to allow constructors for the UsdnProtocolSepolia safeguard mechanism
        if (chain == ChainId.Sepolia) {
            opts.unsafeAllow = "constructor,external-library-linking";
            contractName = "UsdnProtocolSepolia.sol";
        } else {
            opts.unsafeAllow = "external-library-linking";
            contractName = "UsdnProtocolImpl.sol";
        }

        // deploy the protocol fallback
        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        UsdnProtocolImpl usdnProtocolImpl = new UsdnProtocolImpl();
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(usdnProtocolImpl),
            abi.encodeCall(
                UsdnProtocolImpl.initializeStorage,
                (
                    usdn,
                    sdex,
                    wstETH,
                    wstEthOracleMiddleware,
                    liquidationRewardsManager,
                    100, // tick spacing 100 = 1%
                    feeCollector,
                    Types.Roles({
                        setExternalAdmin: deployerAddress,
                        criticalFunctionsAdmin: deployerAddress,
                        setProtocolParamsAdmin: deployerAddress,
                        setUsdnParamsAdmin: deployerAddress,
                        setOptionsAdmin: deployerAddress
                    }),
                    protocolFallback
                )
            )
        );

        usdnProtocol_ = IUsdnProtocol(proxy);
    }

    /**
     * @notice Deploy the liquidation rewards manager if necessary
     * @dev Will return the already deployed one if an address is in the env variables
     * @param isProdEnv Env check
     * @param wstETHAddress The address of the WstETH token
     * @return liquidationRewardsManager_ The deployed contract
     */
    function _deployLiquidationRewardsManager(bool isProdEnv, address wstETHAddress)
        internal
        returns (LiquidationRewardsManager liquidationRewardsManager_)
    {
        address liquidationRewardsManagerAddress = vm.envOr("LIQUIDATION_REWARDS_MANAGER_ADDRESS", address(0));
        if (liquidationRewardsManagerAddress != address(0)) {
            if (isProdEnv) {
                liquidationRewardsManager_ = LiquidationRewardsManager(liquidationRewardsManagerAddress);
            } else {
                liquidationRewardsManager_ = MockLiquidationRewardsManager(liquidationRewardsManagerAddress);
            }
        } else {
            address chainlinkGasPriceFeed = vm.envAddress("CHAINLINK_GAS_PRICE_ADDRESS");
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_GAS_PRICE_VALIDITY", uint256(2 hours + 5 minutes));

            if (isProdEnv) {
                liquidationRewardsManager_ =
                    new LiquidationRewardsManager(chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity);
            } else {
                liquidationRewardsManager_ = new MockLiquidationRewardsManager(
                    chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity
                );
            }
        }
    }

    /**
     * @notice Deploy the WstETH oracle middleware if necessary
     * @dev Will return the already deployed one if an address is in the env variables
     * @param isProdEnv Env check
     * @param wstETHAddress The address of the WstETH token
     * @return wstEthOracleMiddleware_ The deployed contract
     */
    function _deployWstEthOracleMiddleware(bool isProdEnv, address wstETHAddress)
        internal
        returns (WstEthOracleMiddleware wstEthOracleMiddleware_)
    {
        address middlewareAddress = vm.envOr("MIDDLEWARE_ADDRESS", address(0));
        if (middlewareAddress != address(0)) {
            if (isProdEnv) {
                wstEthOracleMiddleware_ = WstEthOracleMiddleware(middlewareAddress);
            } else {
                wstEthOracleMiddleware_ = MockWstEthOracleMiddleware(middlewareAddress);
            }
        } else {
            address pythAddress = vm.envAddress("PYTH_ADDRESS");
            bytes32 pythFeedId = vm.envBytes32("PYTH_ETH_FEED_ID");
            address chainlinkPriceAddress = vm.envAddress("CHAINLINK_ETH_PRICE_ADDRESS");
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_ETH_PRICE_VALIDITY", uint256(1 hours + 2 minutes));

            if (isProdEnv) {
                wstEthOracleMiddleware_ = new WstEthOracleMiddleware(
                    pythAddress, pythFeedId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
                );
            } else {
                wstEthOracleMiddleware_ = new MockWstEthOracleMiddleware(
                    pythAddress, pythFeedId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
                );
            }
        }
    }

    /**
     * @notice Handle the deployment of the periphery contracts for Sepolia
     * @param wstEthNeeded The amount of WstETH needed for the initialization
     * @return usdn_ The USDN token
     * @return wusdn_ The WUSDN token
     * @return sdex_ The SDEX token
     * @return wstETH_ The WstETH token
     */
    function _handlePeripherySepoliaDeployment(uint256 wstEthNeeded)
        internal
        returns (Usdn usdn_, Wusdn wusdn_, Sdex sdex_, WstETH wstETH_)
    {
        uint256 stEthPerToken = utils.getStEthPerTokenMainnet();

        SdexSepolia sdex = new SdexSepolia();
        WstETHSepolia wsteth = new WstETHSepolia();
        MockFastGasGwei mockFastGasGwei = new MockFastGasGwei();
        // mint needed wstETH for the initialization to the deployer
        wsteth.mint(deployerAddress, wstEthNeeded);

        wsteth.setStEthPerToken(stEthPerToken);
        usdn_ = new Usdn(address(0), address(0));
        wusdn_ = new Wusdn(usdn_);

        sdex_ = Sdex(address(sdex));
        wstETH_ = WstETH(payable(address(wsteth)));

        vm.setEnv("PYTH_ADDRESS", "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21");
        vm.setEnv("PYTH_ETH_FEED_ID", "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace");
        vm.setEnv("CHAINLINK_ETH_PRICE_ADDRESS", "0x694AA1769357215DE4FAC081bf1f309aDC325306");
        vm.setEnv("CHAINLINK_GAS_PRICE_ADDRESS", vm.toString(address(mockFastGasGwei)));
    }

    /**
     * @notice Get the initial amounts for the protocol initialization
     * @return depositAmount The amount to deposit
     * @return longAmount The size of the long
     */
    function _getInitialAmounts() internal view returns (uint256 depositAmount, uint256 longAmount) {
        if (chainId == ChainId.Sepolia) {
            depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(200 ether));
            longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(200 ether));
        } else {
            try vm.envUint("INIT_DEPOSIT_AMOUNT") {
                depositAmount = vm.envUint("INIT_DEPOSIT_AMOUNT");
            } catch {
                revert("INIT_DEPOSIT_AMOUNT is required");
            }
            try vm.envUint("INIT_LONG_AMOUNT") {
                longAmount = vm.envUint("INIT_LONG_AMOUNT");
            } catch {
                revert("INIT_DEPOSIT_AMOUNT is required");
            }
        }
    }

    /**
     * @notice Handle the environment variables
     */
    function _handleEnvVariables() internal {
        try vm.envAddress("DEPLOYER_ADDRESS") {
            deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        feeCollector = vm.envOr("FEE_COLLECTOR", deployerAddress);

        string memory etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string("XXXXXXXXXXXXXXXXX"));
        vm.setEnv("ETHERSCAN_API_KEY", etherscanApiKey);
    }
}
