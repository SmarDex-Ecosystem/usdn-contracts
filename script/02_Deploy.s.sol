// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";

import { Utils } from "./Utils.s.sol";

import { LiquidationRewardsManager } from "../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockFastGasGwei } from "../src/OracleMiddleware/mock/MockFastGasGwei.sol";
import { MockLiquidationRewardsManager } from "../src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";
import { MockWstEthOracleMiddleware } from "../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { Wusdn } from "../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";
import { WstETH as WstETHSepolia } from "../src/utils/sepolia/tokens/WstETH.sol";

contract Deploy is Script {
    Utils utils = new Utils();
    address deployerAddress;
    address feeCollector;
    ChainId chainId;

    enum ChainId {
        Mainnet,
        Sepolia,
        Fork
    }

    /**
     * @notice Deploy the USDN ecosystem
     * @return WstETH_ The WstETH token
     * @return Sdex_ The SDEX token
     * @return WstEthOracleMiddleware_ The WstETH oracle middleware
     * @return LiquidationRewardsManager_ The liquidation rewards manager
     * @return Rebalancer_ The rebalancer
     * @return Usdn_ The USDN token
     * @return Wusdn_ The WUSDN token
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
            Wusdn Wusdn_,
            IUsdnProtocol UsdnProtocol_
        )
    {
        // validate the Usdn protocol before deploying it
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

        if (chainId == ChainId.Sepolia) {
            (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripherySepoliaDeployment(depositAmount + longAmount);
        } else {
            (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripheryDeployment(depositAmount, longAmount);
        }

        // deploy contracts
        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware(isProdEnv, address(WstETH_));
        LiquidationRewardsManager_ = _deployLiquidationRewardsManager(isProdEnv, address(WstETH_));

        // deploy the USDN protocol
        UsdnProtocol_ =
            _deployProtocol(Usdn_, Sdex_, WstETH_, WstEthOracleMiddleware_, LiquidationRewardsManager_, chainId);

        // deploy the rebalancer
        Rebalancer_ = _deployRebalancer(UsdnProtocol_);

        _handlePostDeployment(UsdnProtocol_, Usdn_, Rebalancer_);

        if (depositAmount > 0 && longAmount > 0) {
            vm.startBroadcast(deployerAddress);
            _initializeUsdnProtocol(
                isProdEnv, UsdnProtocol_, WstETH_, WstEthOracleMiddleware_, depositAmount, longAmount
            );
            vm.stopBroadcast();
        }
    }

    function _deployProtocol(
        Usdn usdn,
        Sdex sdex,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager,
        ChainId chain
    ) internal returns (IUsdnProtocol usdnProtocol_) {
        // clean and build contracts for openzeppelin module
        utils.cleanAndBuildContracts();

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

        vm.startBroadcast(deployerAddress);

        // deploy the protocol fallback
        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();

        address proxy = Upgrades.deployUUPSProxy(
            contractName,
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
            ),
            opts
        );

        vm.stopBroadcast();

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

            vm.startBroadcast(deployerAddress);

            if (isProdEnv) {
                wstEthOracleMiddleware_ = new WstEthOracleMiddleware(
                    pythAddress, pythFeedId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
                );
            } else {
                wstEthOracleMiddleware_ = new MockWstEthOracleMiddleware(
                    pythAddress, pythFeedId, chainlinkPriceAddress, wstETHAddress, chainlinkPriceValidity
                );
            }

            vm.stopBroadcast();
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

            vm.startBroadcast(deployerAddress);

            if (isProdEnv) {
                liquidationRewardsManager_ =
                    new LiquidationRewardsManager(chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity);
            } else {
                liquidationRewardsManager_ = new MockLiquidationRewardsManager(
                    chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity
                );
            }

            vm.stopBroadcast();
        }
    }

    /**
     * @notice Deploy the USDN token
     * @dev Will return the already deployed one if an address is in the env variables
     * @return usdn_ The deployed contract
     */
    function _deployUsdnAndWusdn() internal returns (Usdn usdn_, Wusdn wusdn_) {
        if (chainId == ChainId.Mainnet) {
            uint64 nounce = vm.getNonce(deployerAddress);
            require(nounce == 0, "Nounce must be 0 on mainnet");
        }

        vm.startBroadcast(deployerAddress);

        usdn_ = new Usdn(address(0), address(0));
        wusdn_ = new Wusdn(usdn_);

        vm.stopBroadcast();
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
            vm.startBroadcast(deployerAddress);
            sdex_ = new Sdex();
            vm.stopBroadcast();
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

                vm.startBroadcast(deployerAddress);
                (bool result,) = wstETHAddress.call{ value: ethAmount }(hex"");
                vm.stopBroadcast();

                require(result, "Failed to mint wstETH");
            }
        } else {
            vm.startBroadcast(deployerAddress);
            wstEth_ = new WstETH();
            vm.stopBroadcast();
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
            vm.startBroadcast(deployerAddress);
            rebalancer_ = new Rebalancer(usdnProtocol);
            vm.stopBroadcast();
        }
    }

    /**
     * @notice Initialize the USDN Protocol
     * @param isProdEnv Env check
     * @param usdnProtocol The USDN protocol
     * @param wstETH The WstETH token
     * @param wstEthOracleMiddleware The WstETH oracle middleware
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     */
    function _initializeUsdnProtocol(
        bool isProdEnv,
        IUsdnProtocol usdnProtocol,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        uint256 depositAmount,
        uint256 longAmount
    ) internal {
        uint256 desiredLiqPrice;
        if (isProdEnv) {
            desiredLiqPrice = vm.envUint("INIT_LONG_LIQPRICE");
        } else {
            // for forks, we want a leverage of ~2x so we get the current
            // price from the middleware and divide it by two
            desiredLiqPrice = wstEthOracleMiddleware.parseAndValidatePrice(
                "", uint128(block.timestamp), Types.ProtocolAction.Initialize, ""
            ).price / 2;
        }

        // approve wstETH spending for initialization
        wstETH.approve(address(usdnProtocol), depositAmount + longAmount);
        usdnProtocol.initialize(uint128(depositAmount), uint128(longAmount), uint128(desiredLiqPrice), "");
    }

    function _handlePeripheryDeployment(uint256 depositAmount, uint256 longAmount)
        internal
        returns (Usdn usdn_, Wusdn wusdn_, Sdex sdex_, WstETH wstETH_)
    {
        (usdn_, wusdn_) = _deployUsdnAndWusdn();
        wstETH_ = _deployWstETH(depositAmount, longAmount);
        sdex_ = _deploySdex();
    }

    function _handlePostDeployment(IUsdnProtocol usdnProtocol, Usdn usdn, Rebalancer rebalancer) internal {
        vm.startBroadcast(deployerAddress);

        // set the rebalancer on the USDN protocol
        usdnProtocol.setRebalancer(rebalancer);

        // grant USDN minter and rebaser roles to protocol
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        // renounce admin role on the USDN token, no-one can later change roles
        usdn.renounceRole(usdn.DEFAULT_ADMIN_ROLE(), deployerAddress);

        vm.stopBroadcast();
    }

    function _handlePeripherySepoliaDeployment(uint256 wstEthNeeded)
        internal
        returns (Usdn usdn_, Wusdn wusdn_, Sdex sdex_, WstETH wstETH_)
    {
        vm.startBroadcast(deployerAddress);

        SdexSepolia sdex = new SdexSepolia();
        WstETHSepolia wsteth = new WstETHSepolia();
        MockFastGasGwei mockFastGasGwei = new MockFastGasGwei();
        // mint needed wstETH for the initialisation to the deployer
        wsteth.mint(deployerAddress, wstEthNeeded);

        vm.stopBroadcast();

        uint256 stEthPerToken = utils.getStEthPerTokenMainet();

        vm.startBroadcast(deployerAddress);

        wsteth.setStEthPerToken(stEthPerToken);
        usdn_ = new Usdn(address(0), address(0));
        wusdn_ = new Wusdn(usdn_);

        vm.stopBroadcast();

        uint256 ethPrice = utils.getLastChailinkEthPriceSepolia();
        // ~2x leverage
        uint256 liqPrice = ethPrice * stEthPerToken / 2e18;

        sdex_ = Sdex(address(sdex));
        wstETH_ = WstETH(payable(address(wsteth)));

        vm.setEnv("PYTH_ADDRESS", "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21");
        vm.setEnv("PYTH_ETH_FEED_ID", "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace");
        vm.setEnv("CHAINLINK_ETH_PRICE_ADDRESS", "0x694AA1769357215DE4FAC081bf1f309aDC325306");
        vm.setEnv("CHAINLINK_GAS_PRICE_ADDRESS", vm.toString(address(mockFastGasGwei)));
        vm.setEnv("INIT_LONG_LIQPRICE", vm.toString(liqPrice));
    }

    function _handleEnvVariables() internal {
        try vm.envAddress("DEPLOYER_ADDRESS") {
            deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        try vm.envAddress("FEE_COLLECTOR") {
            feeCollector = vm.envAddress("FEE_COLLECTOR");
        } catch {
            feeCollector = deployerAddress;
        }

        try vm.envString("ETHERSCAN_API_KEY") { }
        catch {
            // not needed but needs to exist
            vm.setEnv("ETHERSCAN_API_KEY", "XXXXXXXXXXXXXXXXX");
        }
    }

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
}
