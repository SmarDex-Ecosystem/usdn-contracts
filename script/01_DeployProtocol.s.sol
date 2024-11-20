// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";

import { Utils } from "./utils/Utils.s.sol";

import { LiquidationRewardsManager } from "../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockWstEthOracleMiddleware } from "../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { Wusdn } from "../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../src/libraries/HugeUint.sol";

contract DeployProtocol is Script {
    address constant WSTETH_MAINNET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant SDEX_MAINNET = 0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF;
    address constant PYTH_MAINNET = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 constant PYTH_ETH_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    address constant CHAINLINK_ETH_PRICE_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    uint256 constant CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
    uint256 constant CHAINLINK_GAS_PRICE_VALIDITY = 2 hours + 5 minutes;

    Utils internal _utils = new Utils();
    address internal _deployerAddress;
    address internal _feeCollector;
    bool internal _isProdEnv;
    uint256 internal _longAmount;

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
        _handleEnvVariables();

        _isProdEnv = block.chainid == 1;

        // internal validation of the Usdn protocol
        _utils.validateProtocol("UsdnProtocolImpl.sol", "UsdnProtocolFallback.sol");

        vm.startBroadcast(_deployerAddress);

        (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripheryDeployment();

        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware(address(WstETH_));

        LiquidationRewardsManager_ = _deployLiquidationRewardsManager(address(WstETH_));

        // we need to stop the broadcast before the OZ validation of the Usdn protocol
        vm.stopBroadcast();

        UsdnProtocol_ = _deployProtocol(Usdn_, Sdex_, WstETH_, WstEthOracleMiddleware_, LiquidationRewardsManager_);

        vm.startBroadcast(_deployerAddress);

        Rebalancer_ = _deployRebalancer(UsdnProtocol_);

        _handlePostDeployment(UsdnProtocol_, Usdn_, Rebalancer_);

        _initializeUsdnProtocol(UsdnProtocol_, WstETH_, WstEthOracleMiddleware_);

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

        // we need to allow external library linking and immutable variables in the openzeppelin module
        Options memory opts;
        opts.unsafeAllow = "external-library-linking,state-variable-immutable";

        vm.startBroadcast(_deployerAddress);

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
                    100, // tick spacing 100 = 1.05%
                    _feeCollector,
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
     * @param wstETHAddress The address of the WstETH token
     * @return wstEthOracleMiddleware_ The deployed contract
     */
    function _deployWstEthOracleMiddleware(address wstETHAddress)
        internal
        returns (WstEthOracleMiddleware wstEthOracleMiddleware_)
    {
        address middlewareAddress = vm.envOr("MIDDLEWARE_ADDRESS", address(0));

        if (middlewareAddress != address(0)) {
            if (_isProdEnv) {
                wstEthOracleMiddleware_ = WstEthOracleMiddleware(middlewareAddress);
            } else {
                wstEthOracleMiddleware_ = MockWstEthOracleMiddleware(middlewareAddress);
            }
        } else {
            address pythAddress = vm.envOr("PYTH_ADDRESS", PYTH_MAINNET);
            bytes32 pythFeedId = vm.envOr("PYTH_ETH_FEED_ID", PYTH_ETH_FEED_ID);
            address chainlinkPriceAddress = vm.envOr("CHAINLINK_ETH_PRICE_ADDRESS", CHAINLINK_ETH_PRICE_MAINNET);
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_ETH_PRICE_VALIDITY", CHAINLINK_PRICE_VALIDITY);

            if (_isProdEnv) {
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
     * @param wstETHAddress The address of the WstETH token
     * @return liquidationRewardsManager_ The deployed contract
     */
    function _deployLiquidationRewardsManager(address wstETHAddress)
        internal
        returns (LiquidationRewardsManager liquidationRewardsManager_)
    {
        address liquidationRewardsManagerAddress = vm.envOr("LIQUIDATION_REWARDS_MANAGER_ADDRESS", address(0));

        if (liquidationRewardsManagerAddress != address(0)) {
            liquidationRewardsManager_ = LiquidationRewardsManager(liquidationRewardsManagerAddress);
        } else {
            liquidationRewardsManager_ = new LiquidationRewardsManager(IWstETH(wstETHAddress));
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
        address usdnAddress = payable(vm.envOr("USDN_ADDRESS", address(0)));

        if (usdnAddress != address(0)) {
            usdn_ = Usdn(usdnAddress);
        } else {
            if (_isProdEnv) {
                revert("USDN_ADDRESS is required on mainnet");
            }
            usdn_ = new Usdn(address(0), address(0));
        }

        wusdn_ = new Wusdn(usdn_);
    }

    /**
     * @notice Deploy the SDEX token
     * @dev Will return the already deployed one if an address is in the env variables
     * Will use the mainnet address if the chainId is mainnet
     * @return sdex_ The deployed contract
     */
    function _deploySdex() internal returns (Sdex sdex_) {
        if (_isProdEnv) {
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
     * @return wstEth_ The deployed contract
     */
    function _deployWstETH() internal returns (WstETH wstEth_) {
        if (_isProdEnv) {
            return WstETH(payable(WSTETH_MAINNET));
        }

        address payable wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        if (wstETHAddress != address(0)) {
            wstEth_ = WstETH(wstETHAddress);
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
     * @notice Initialize the USDN Protocol by opening a long and depositing the necessary amount
     * @dev The deposit amount is calculated to reach a balanced state with a leverage of ~2x on the long position
     * @param usdnProtocol The USDN protocol
     * @param wstETH The WstETH token
     * @param wstEthOracleMiddleware The WstETH oracle middleware
     */
    function _initializeUsdnProtocol(
        IUsdnProtocol usdnProtocol,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware
    ) internal {
        uint24 liquidationPenalty = usdnProtocol.getLiquidationPenalty();
        int24 tickSpacing = usdnProtocol.getTickSpacing();
        uint256 price = wstEthOracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), Types.ProtocolAction.Initialize, ""
        ).price;

        // we want a leverage of ~2x so we get the current price from the middleware and divide it by two
        uint128 desiredLiqPrice = uint128(price / 2);
        // get the liquidation price with the tick rounding
        uint128 liqPriceWithoutPenalty = usdnProtocol.getLiqPriceFromDesiredLiqPrice(
            desiredLiqPrice, price, 0, HugeUint.wrap(0), tickSpacing, liquidationPenalty
        );
        // get the total exposure of the wanted long position
        uint256 positionTotalExpo = FixedPointMathLib.fullMulDiv(_longAmount, price, price - liqPriceWithoutPenalty);
        // get the amount to deposit to reach a balanced state
        uint256 depositAmount = positionTotalExpo - _longAmount;

        if (vm.envOr("GET_WSTETH", false)) {
            uint256 ethAmount = (depositAmount + _longAmount + 10_000) * wstETH.stEthPerToken() / 1 ether;
            (bool result,) = address(wstETH).call{ value: ethAmount }(hex"");
            require(result, "Failed to mint wstETH");
        }

        wstETH.approve(address(usdnProtocol), depositAmount + _longAmount);

        usdnProtocol.initialize(uint128(depositAmount), uint128(_longAmount), desiredLiqPrice, "");
    }

    /**
     * @notice Handle post-deployment tasks
     * @param usdnProtocol The USDN protocol
     * @param usdn The USDN token
     * @param rebalancer The rebalancer
     */
    function _handlePostDeployment(IUsdnProtocol usdnProtocol, Usdn usdn, Rebalancer rebalancer) internal {
        // grant the necessary roles to the deployer to set the rebalancer and then revoke them
        bytes32 ADMIN_SET_EXTERNAL_ROLE = Constants.ADMIN_SET_EXTERNAL_ROLE;
        bytes32 SET_EXTERNAL_ROLE = Constants.SET_EXTERNAL_ROLE;
        usdnProtocol.grantRole(ADMIN_SET_EXTERNAL_ROLE, _deployerAddress);
        usdnProtocol.grantRole(SET_EXTERNAL_ROLE, _deployerAddress);

        usdnProtocol.setRebalancer(rebalancer);

        usdnProtocol.revokeRole(SET_EXTERNAL_ROLE, _deployerAddress);
        usdnProtocol.revokeRole(ADMIN_SET_EXTERNAL_ROLE, _deployerAddress);

        // grant the minter and rebaser roles to the protocol and then renounce the admin role of the deployer
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        usdn.renounceRole(usdn.DEFAULT_ADMIN_ROLE(), _deployerAddress);
    }

    /**
     * @notice Handle the deployment of the periphery contracts
     * @return usdn_ The USDN token
     * @return wusdn_ The WUSDN token
     * @return sdex_ The SDEX token
     * @return wstETH_ The WstETH token
     */
    function _handlePeripheryDeployment() internal returns (Usdn usdn_, Wusdn wusdn_, Sdex sdex_, WstETH wstETH_) {
        (usdn_, wusdn_) = _deployUsdnAndWusdn();
        wstETH_ = _deployWstETH();
        sdex_ = _deploySdex();
    }

    /// @notice Handle the environment variables
    function _handleEnvVariables() internal {
        // mandatory env variables : DEPLOYER_ADDRESS and INIT_LONG_AMOUNT
        try vm.envAddress("DEPLOYER_ADDRESS") {
            _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        try vm.envUint("INIT_LONG_AMOUNT") {
            _longAmount = vm.envUint("INIT_LONG_AMOUNT");
        } catch {
            revert("INIT_LONG_AMOUNT is required");
        }

        // optional env variables
        _feeCollector = vm.envOr("FEE_COLLECTOR", _deployerAddress);
        string memory etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string("XXXXXXXXXXXXXXXXX"));
        vm.setEnv("ETHERSCAN_API_KEY", etherscanApiKey);
    }
}
