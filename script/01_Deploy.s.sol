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
import { UsdnProtocolFallbackSepolia } from "../src/UsdnProtocol/UsdnProtocolFallbackSepolia.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";
import { WstETH as WstETHSepolia } from "../src/utils/sepolia/tokens/WstETH.sol";

contract Deploy is Script {
    address constant WSTETH_MAINNET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant SDEX_MAINNET = 0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF;
    address constant PYTH_SEPOLIA = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21;
    address constant PYTH_MAINNET = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 constant PYTH_ETH_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    address constant CHAINLINK_ETH_PRICE_SEPOLIA = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant CHAINLINK_ETH_PRICE_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CHAINLINK_GAS_MAINNET = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
    uint256 constant CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
    uint256 constant CHAINLINK_GAS_PRICE_VALIDITY = 2 hours + 5 minutes;

    Utils _utils = new Utils();
    address _deployerAddress;
    address _feeCollector;
    ChainId _chainId;

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
        _utils.validateProtocol();

        if (block.chainid == 1) {
            _chainId = ChainId.Mainnet;
        } else if (block.chainid == 11_155_111) {
            _chainId = ChainId.Sepolia;
        } else {
            _chainId = ChainId.Fork;
        }

        _handleEnvVariables();

        bool isProdEnv = _chainId != ChainId.Fork;

        (uint256 depositAmount, uint256 longAmount) = _getInitialAmounts();

        vm.startBroadcast(_deployerAddress);

        if (_chainId == ChainId.Sepolia) {
            (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripherySepoliaDeployment(depositAmount + longAmount);
        } else {
            (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripheryDeployment(depositAmount, longAmount);
        }

        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware(isProdEnv, address(WstETH_));
        LiquidationRewardsManager_ = _deployLiquidationRewardsManager(isProdEnv, address(WstETH_));

        // deploy the USDN protocol
        UsdnProtocol_ = _deployProtocol(Usdn_, Sdex_, WstETH_, WstEthOracleMiddleware_, LiquidationRewardsManager_);

        // deploy the rebalancer
        Rebalancer_ = _deployRebalancer(UsdnProtocol_);

        _handlePostDeployment(UsdnProtocol_, Usdn_, Rebalancer_);

        _initializeUsdnProtocol(UsdnProtocol_, WstETH_, WstEthOracleMiddleware_, depositAmount, longAmount);

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the USDN protocol
     * @param usdn The USDN token
     * @param sdex The SDEX token
     * @param wstETH The WstETH token
     * @param wstEthOracleMiddleware The WstETH oracle middleware
     * @param liquidationRewardsManager The liquidation rewards manager
     * @return usdnProtocol_ The deployed protocol
     */
    function _deployProtocol(
        Usdn usdn,
        Sdex sdex,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager
    ) internal returns (IUsdnProtocol usdnProtocol_) {
        // clean and build contracts for openzeppelin module
        _utils.cleanAndBuildContracts();

        // we need to allow external library linking for the openzeppelin module
        Options memory opts;
        opts.unsafeAllow = "external-library-linking,state-variable-immutable";

        UsdnProtocolFallback protocolFallback;
        if (_chainId == ChainId.Sepolia) {
            protocolFallback = new UsdnProtocolFallbackSepolia();
        } else {
            protocolFallback = new UsdnProtocolFallback();
        }

        // deploy the protocol fallback

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
                    _feeCollector,
                    Types.Managers({
                        setExternalManager: _deployerAddress,
                        criticalFunctionsManager: _deployerAddress,
                        setProtocolParamsManager: _deployerAddress,
                        setUsdnParamsManager: _deployerAddress,
                        setOptionsManager: _deployerAddress,
                        proxyUpgradeManager: _deployerAddress
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
            address pythAddress = vm.envOr("PYTH_ADDRESS", PYTH_MAINNET);
            bytes32 pythFeedId = vm.envOr("PYTH_ETH_FEED_ID", bytes32(PYTH_ETH_FEED_ID));
            address chainlinkPriceAddress = vm.envOr("CHAINLINK_ETH_PRICE_ADDRESS", CHAINLINK_ETH_PRICE_MAINNET);
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_ETH_PRICE_VALIDITY", CHAINLINK_PRICE_VALIDITY);

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
            address chainlinkGasPriceFeed = vm.envOr("CHAINLINK_GAS_PRICE_ADDRESS", CHAINLINK_GAS_MAINNET);
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_GAS_PRICE_VALIDITY", CHAINLINK_GAS_PRICE_VALIDITY);

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
     * @notice Deploy the USDN token and the WUSDN token
     * @dev Will return the already deployed ones if an address is in the env variables
     * On mainnet the `USDN_ADDRESS` env variable is required
     * @return usdn_ The deployed Usdn contract
     * @return wusdn_ The deployed Wusdn contract
     */
    function _deployUsdnAndWusdn() internal returns (Usdn usdn_, Wusdn wusdn_) {
        if (_chainId == ChainId.Mainnet) {
            try vm.envAddress("USDN_ADDRESS") {
                usdn_ = Usdn(vm.envAddress("USDN_ADDRESS"));
            } catch {
                revert("USDN_ADDRESS is required on mainnet");
            }
        } else {
            usdn_ = new Usdn(address(0), address(0));
        }

        wusdn_ = new Wusdn(usdn_);
    }

    /**
     * @notice Deploy the SDEX token
     * @dev Will return the already deployed one if an address is in the env variables
     * Will use the mainnet address if the chain is mainnet
     * @return sdex_ The deployed contract
     */
    function _deploySdex() internal returns (Sdex sdex_) {
        if (_chainId == ChainId.Mainnet) {
            return Sdex(SDEX_MAINNET);
        }

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
     * Will return the mainnet address if the chain is mainnet
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     * @return wstEth_ The deployed contract
     */
    function _deployWstETH(uint256 depositAmount, uint256 longAmount) internal returns (WstETH wstEth_) {
        address payable wstETHAddress;
        if (_chainId == ChainId.Mainnet) {
            wstETHAddress = payable(WSTETH_MAINNET);
        } else {
            wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        }

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
     * @param usdnProtocol The USDN protocol
     * @param wstETH The WstETH token
     * @param wstEthOracleMiddleware The WstETH oracle middleware
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     */
    function _initializeUsdnProtocol(
        IUsdnProtocol usdnProtocol,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        uint256 depositAmount,
        uint256 longAmount
    ) internal {
        // for forks, we want a leverage of ~2x so we get the current
        // price from the middleware and divide it by two
        uint256 desiredLiqPrice = wstEthOracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), Types.ProtocolAction.Initialize, ""
        ).price / 2;

        // approve wstETH spending for initialization
        wstETH.approve(address(usdnProtocol), depositAmount + longAmount);
        usdnProtocol.initialize(uint128(depositAmount), uint128(longAmount), uint128(desiredLiqPrice), "");
    }

    /**
     * @notice Handle post-deployment tasks
     * @param usdnProtocol The USDN protocol
     * @param usdn The USDN token
     * @param rebalancer The rebalancer
     */
    function _handlePostDeployment(IUsdnProtocol usdnProtocol, Usdn usdn, Rebalancer rebalancer) internal {
        // set the rebalancer on the USDN protocol
        usdnProtocol.setRebalancer(rebalancer);

        // grant USDN minter and rebaser roles to protocol
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        // renounce admin role on the USDN token, no one can later change roles
        usdn.renounceRole(usdn.DEFAULT_ADMIN_ROLE(), _deployerAddress);
    }

    /**
     * @notice Handle the deployment of the periphery contracts
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     * @return usdn_ The USDN token
     * @return wusdn_ The WUSDN token
     * @return sdex_ The SDEX token
     * @return wstETH_ The WstETH token
     */
    function _handlePeripheryDeployment(uint256 depositAmount, uint256 longAmount)
        internal
        returns (Usdn usdn_, Wusdn wusdn_, Sdex sdex_, WstETH wstETH_)
    {
        (usdn_, wusdn_) = _deployUsdnAndWusdn();
        wstETH_ = _deployWstETH(depositAmount, longAmount);
        sdex_ = _deploySdex();
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
        uint256 stEthPerToken = _utils.getStEthPerTokenMainnet();

        SdexSepolia sdex = new SdexSepolia();
        WstETHSepolia wsteth = new WstETHSepolia();
        MockFastGasGwei mockFastGasGwei = new MockFastGasGwei();

        // mint needed wstETH for the initialization to the deployer
        wsteth.mint(_deployerAddress, wstEthNeeded);

        wsteth.setStEthPerToken(stEthPerToken);

        (usdn_, wusdn_) = _deployUsdnAndWusdn();

        sdex_ = Sdex(address(sdex));
        wstETH_ = WstETH(payable(address(wsteth)));

        vm.setEnv("PYTH_ADDRESS", vm.toString(PYTH_SEPOLIA));
        vm.setEnv("PYTH_ETH_FEED_ID", vm.toString(PYTH_ETH_FEED_ID));
        vm.setEnv("CHAINLINK_ETH_PRICE_ADDRESS", vm.toString(CHAINLINK_ETH_PRICE_SEPOLIA));
        vm.setEnv("CHAINLINK_GAS_PRICE_ADDRESS", vm.toString(address(mockFastGasGwei)));
    }

    /**
     * @notice Handle the environment variables
     */
    function _handleEnvVariables() internal {
        try vm.envAddress("DEPLOYER_ADDRESS") {
            _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        _feeCollector = vm.envOr("FEE_COLLECTOR", _deployerAddress);

        string memory etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string("XXXXXXXXXXXXXXXXX"));
        vm.setEnv("ETHERSCAN_API_KEY", etherscanApiKey);
    }

    /**
     * @notice Get the initial amounts for the protocol initialization
     * @return depositAmount The amount to deposit
     * @return longAmount The size of the long
     */
    function _getInitialAmounts() internal view returns (uint256 depositAmount, uint256 longAmount) {
        if (_chainId == ChainId.Sepolia) {
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
