// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";
import { WstETH as WstETHSepolia } from "../src/utils/sepolia/tokens/WstETH.sol";
import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";

import { DeploySepoliaMocks } from "./00_DeploySepoliaMocks.s.sol";
import { Utils } from "./Utils.s.sol";

import { LiquidationRewardsManager } from "../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockFastGasGwei } from "../src/OracleMiddleware/mock/MockFastGasGwei.sol";
import { MockLiquidationRewardsManager } from "../src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";
import { MockWstEthOracleMiddleware } from "../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract Deploy is Script {
    Utils utils = new Utils();
    address deployerAddress;

    enum ChainId {
        mainnet,
        sepolia,
        fork
    }

    /**
     * @notice Deploy the USDN ecosystem
     * @return WstETH_ The WstETH token
     * @return Sdex_ The SDEX token
     * @return WstEthOracleMiddleware_ The WstETH oracle middleware
     * @return LiquidationRewardsManager_ The liquidation rewards manager
     * @return Rebalancer_ The rebalancer
     * @return Usdn_ The USDN token
     * @return UsdnProtocol_ The USDN protocol with fallback
     */
    function run()
        external
        returns (
            WstETH WstETH_,
            Sdex Sdex_,
            WstEthOracleMiddleware WstEthOracleMiddleware_,
            LiquidationRewardsManager LiquidationRewardsManager_,
            Rebalancer Rebalancer_,
            Usdn Usdn_,
            IUsdnProtocol UsdnProtocol_
        )
    {
        // validate the Usdn protocol before deploying it
        bool success = utils.validateProtocol();
        require(success, "Protocol validation failed");

        try vm.envAddress("DEPLOYER_ADDRESS") {
            deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        try vm.envString("ETHERSCAN_API_KEY") { }
        catch {
            // TO DO : verify that still needed
            // not needed but needs to exist
            vm.setEnv("ETHERSCAN_API_KEY", "XXXXXXXXXXXXXXXXX");
        }

        ChainId chain;
        if (block.chainid == 1) {
            chain = ChainId.mainnet;
        } else if (block.chainid == 11_155_111) {
            chain = ChainId.sepolia;
        } else {
            chain = ChainId.fork;
        }

        bool isProdEnv = chain != ChainId.fork;

        uint256 depositAmount;
        uint256 longAmount;
        if (chain == ChainId.sepolia) {
            depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(200 ether));
            longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(200 ether));
        } else {
            depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(0));
            longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(0));
        }

        if (chain == ChainId.sepolia) {
            DeploySepoliaMocks deploySepoliaMocks = new DeploySepoliaMocks();
            (SdexSepolia sdex, WstETHSepolia wsteth, MockFastGasGwei mockFastGasGwei) =
                deploySepoliaMocks.run(deployerAddress, depositAmount + longAmount);

            string[] memory inputs = new string[](6);
            inputs[0] = "cast";
            inputs[1] = "call";
            inputs[2] = "-r";
            inputs[3] = vm.envString("RPC_URL");
            inputs[4] = "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0";
            inputs[5] = "stEthPerToken()";
            bytes memory result = vm.ffi(inputs);
            uint256 stEthPerToken = abi.decode(result, (uint256));
            vm.startBroadcast(deployerAddress);
            wsteth.setStEthPerToken(stEthPerToken);
            vm.stopBroadcast();

            Usdn_ = new Usdn(address(0), address(0));

            string[] memory inputs2 = new string[](6);
            inputs2[0] = "cast";
            inputs2[1] = "call";
            inputs2[2] = "-r";
            inputs2[3] = vm.envString("RPC_URL");
            inputs2[4] = "0x694AA1769357215DE4FAC081bf1f309aDC325306";
            inputs2[5] = "latestAnswer()";
            result = vm.ffi(inputs2);
            uint256 ethPrice = abi.decode(result, (uint256));
            ethPrice *= 10_000_000_000;
            uint256 liqPrice = ethPrice * stEthPerToken / 2_000_000_000_000_000_000;

            Sdex_ = Sdex(address(sdex));
            WstETH_ = WstETH(payable(address(wsteth)));

            vm.setEnv("PYTH_ADDRESS", "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21");
            vm.setEnv("PYTH_ETH_FEED_ID", "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace");
            vm.setEnv("CHAINLINK_ETH_PRICE_ADDRESS", "0x694AA1769357215DE4FAC081bf1f309aDC325306");
            vm.setEnv("FEE_COLLECTOR", vm.toString(deployerAddress));
            vm.setEnv("CHAINLINK_ETH_PRICE_VALIDITY", "3720");
            vm.setEnv("CHAINLINK_GAS_PRICE_ADDRESS", vm.toString(address(mockFastGasGwei)));
            vm.setEnv("CHAINLINK_GAS_PRICE_VALIDITY", "7500");
            vm.setEnv("INIT_LONG_LIQPRICE", vm.toString(liqPrice));
        } else {
            vm.startBroadcast(deployerAddress);

            WstETH_ = _deployWstETH(depositAmount, longAmount);
            Usdn_ = _deployUsdn(isProdEnv);
            Sdex_ = _deploySdex();

            vm.stopBroadcast();
        }

        vm.startBroadcast(deployerAddress);

        // deploy contracts
        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware(isProdEnv, address(WstETH_));
        LiquidationRewardsManager_ = _deployLiquidationRewardsManager(isProdEnv, address(WstETH_));

        // deploy the USDN protocol
        UsdnProtocol_ = _deployProtocol(Usdn_, Sdex_, WstETH_, WstEthOracleMiddleware_, LiquidationRewardsManager_);

        // deploy the rebalancer
        Rebalancer_ = _deployRebalancer(UsdnProtocol_);

        // set the rebalancer on the USDN protocol
        UsdnProtocol_.setRebalancer(Rebalancer_);

        // grant USDN minter and rebaser roles to protocol
        Usdn_.grantRole(Usdn_.MINTER_ROLE(), address(UsdnProtocol_));
        Usdn_.grantRole(Usdn_.REBASER_ROLE(), address(UsdnProtocol_));
        // renounce admin role on the USDN token, no-one can later change roles
        Usdn_.renounceRole(Usdn_.DEFAULT_ADMIN_ROLE(), deployerAddress);

        // approve wstETH spending for initialization
        WstETH_.approve(address(UsdnProtocol_), depositAmount + longAmount);

        if (depositAmount > 0 && longAmount > 0) {
            _initializeUsdnProtocol(isProdEnv, UsdnProtocol_, WstEthOracleMiddleware_, depositAmount, longAmount);
        }

        vm.stopBroadcast();
    }

    function _deployProtocol(
        Usdn usdn,
        Sdex sdex,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager
    ) internal returns (IUsdnProtocol usdnProtocol_) {
        // we need to allow external library linking for the openzeppelin module
        Options memory opts;
        // we need to allow constructors for the UsdnProtocolSepolia safeguard mechanism
        opts.unsafeAllow = "constructor,external-library-linking";

        // deploy the protocol fallback
        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();

        address proxy = Upgrades.deployUUPSProxy(
            "UsdnProtocolImpl.sol",
            abi.encodeCall(
                UsdnProtocolImpl.initializeStorage,
                (
                    usdn,
                    sdex,
                    wstETH,
                    wstEthOracleMiddleware,
                    liquidationRewardsManager,
                    100, // tick spacing 100 = 1%
                    vm.envAddress("FEE_COLLECTOR"),
                    Types.Roles({
                        setExternalAdmin: deployerAddress,
                        criticalFunctionsAdmin: deployerAddress,
                        setProtocolParamsAdmin: deployerAddress,
                        setUsdnParamsAdmin: deployerAddress,
                        setOptionsAdmin: deployerAddress
                    }),
                    protocolFallback
                )
            ),
            opts
        );

        usdnProtocol_ = IUsdnProtocol(proxy);
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
     * @notice Deploy the USDN token
     * @dev Will return the already deployed one if an address is in the env variables
     * @return usdn_ The deployed contract
     */
    function _deployUsdn(bool isProdEnv) internal returns (Usdn usdn_) {
        if (isProdEnv) {
            // in production environment, we want to deploy the USDN token separately via `01_DeployUsdn.s.sol`
            address usdnAddress = vm.envAddress("USDN_ADDRESS");
            require(usdnAddress != address(0), "USDN_ADDRESS is required in prod mode");
            usdn_ = Usdn(usdnAddress);
        } else {
            usdn_ = new Usdn(address(0), address(0));
        }
    }

    /**
     * @notice Deploy the SDEX token
     * @dev Will return the already deployed one if an address is in the env variables
     * @return sdex_ The deployed contract
     */
    function _deploySdex() internal returns (Sdex sdex_) {
        address sdexAddress = payable(vm.envOr("SDEX_ADDRESS", address(0)));
        if (sdexAddress != address(0)) {
            sdex_ = Sdex(sdexAddress);
        } else {
            sdex_ = new Sdex();
        }
    }

    /**
     * @notice Deploy the WstETH token
     * @dev Will return the already deployed one if an address is in the env variables
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     * @return wstEth_ The deployed contract
     */
    function _deployWstETH(uint256 depositAmount, uint256 longAmount) internal returns (WstETH wstEth_) {
        address payable wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        if (wstETHAddress != address(0)) {
            wstEth_ = WstETH(wstETHAddress);
            if (vm.envOr("GET_WSTETH", false) && depositAmount > 0 && longAmount > 0) {
                uint256 ethAmount = (depositAmount + longAmount + 10_000) * wstEth_.stEthPerToken() / 1 ether;
                (bool result,) = wstETHAddress.call{ value: ethAmount }(hex"");
                require(result, "Failed to mint wstETH");
            }
        } else {
            wstEth_ = new WstETH();
        }
    }

    /**
     * @notice Deploy the Rebalancer contract if necessary
     * @dev Will return the already deployed one if an address is in the env variables
     * @param usdnProtocol The USDN protocol
     * @return rebalancer_ The deployed contract
     */
    function _deployRebalancer(IUsdnProtocol usdnProtocol) internal returns (Rebalancer rebalancer_) {
        address payable rebalancerAddress = payable(vm.envOr("REBALANCER_ADDRESS", address(0)));
        if (rebalancerAddress != address(0)) {
            rebalancer_ = Rebalancer(rebalancerAddress);
        } else {
            rebalancer_ = new Rebalancer(usdnProtocol);
        }
    }

    /**
     * @notice Initialize the USDN Protocol
     * @param isProdEnv Env check
     * @param UsdnProtocol_ The USDN protocol
     * @param WstEthOracleMiddleware_ The WstETH oracle middleware
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     */
    function _initializeUsdnProtocol(
        bool isProdEnv,
        IUsdnProtocol UsdnProtocol_,
        WstEthOracleMiddleware WstEthOracleMiddleware_,
        uint256 depositAmount,
        uint256 longAmount
    ) internal {
        uint256 desiredLiqPrice;
        if (isProdEnv) {
            desiredLiqPrice = vm.envUint("INIT_LONG_LIQPRICE");
        } else {
            // for forks, we want a leverage of ~2x so we get the current
            // price from the middleware and divide it by two
            desiredLiqPrice = WstEthOracleMiddleware_.parseAndValidatePrice(
                "", uint128(block.timestamp), Types.ProtocolAction.Initialize, ""
            ).price / 2;
        }

        UsdnProtocol_.initialize(uint128(depositAmount), uint128(longAmount), uint128(desiredLiqPrice), "");
    }
}
