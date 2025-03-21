// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";

import { Utils } from "./utils/Utils.s.sol";

import { LiquidationRewardsManagerWstEth } from "../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";
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

contract DeployProtocol is Script {
    address constant WSTETH_MAINNET = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant SDEX_MAINNET = 0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF;
    address constant USDN_MAINNET = 0xde17a000BA631c5d7c2Bd9FB692EFeA52D90DEE2;
    address constant WUSDN_MAINNET = 0x99999999999999Cc837C997B882957daFdCb1Af9;
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
    address internal _safeAddress;

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
            LiquidationRewardsManagerWstEth LiquidationRewardsManager_,
            Rebalancer Rebalancer_,
            Usdn Usdn_,
            Wusdn Wusdn_,
            IUsdnProtocol UsdnProtocol_
        )
    {
        _handleEnvVariables();

        // internal validation of the Usdn protocol
        _utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        vm.startBroadcast(_deployerAddress);

        (Usdn_, Wusdn_, Sdex_, WstETH_) = _handlePeripheryDeployment();

        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware(address(WstETH_));

        LiquidationRewardsManager_ = _deployLiquidationRewardsManager(address(WstETH_));

        // we need to stop the broadcast before the OZ validation of the Usdn protocol
        vm.stopBroadcast();

        Types.InitStorage memory initStorage;
        UsdnProtocol_ = _deployProtocol(initStorage);

        vm.startBroadcast(_deployerAddress);

        Rebalancer_ = _deployRebalancer(UsdnProtocol_);

        if (_isProdEnv) {
            _handlePostDeployment(UsdnProtocol_, Rebalancer_, WstEthOracleMiddleware_, LiquidationRewardsManager_);
        } else {
            _initializeUsdnProtocolFork(UsdnProtocol_, WstETH_, WstEthOracleMiddleware_, Usdn_, Rebalancer_);
        }

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the USDN protocol
     * @param initStorage The storage initialization parameters
     * @return usdnProtocol_ The deployed protocol
     */
    function _deployProtocol(Types.InitStorage memory initStorage) internal returns (IUsdnProtocol usdnProtocol_) {
        // clean and build contracts for openzeppelin module
        _utils.cleanAndBuildContracts();

        // we need to allow external library linking and immutable variables in the openzeppelin module
        Options memory opts;
        opts.unsafeAllow = "external-library-linking,state-variable-immutable";

        vm.startBroadcast(_deployerAddress);
        // UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        address proxy = Upgrades.deployUUPSProxy(
            "UsdnProtocolImpl.sol", abi.encodeCall(UsdnProtocolImpl.initializeStorage, (initStorage)), opts
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
                uint256 initialWSTETHMockedPrice = vm.envOr("INITIAL_WSTETH_MOCKED_PRICE", uint256(0));
                if (initialWSTETHMockedPrice > 0) {
                    MockWstEthOracleMiddleware(address(wstEthOracleMiddleware_)).setVerifySignature(false);
                    MockWstEthOracleMiddleware(address(wstEthOracleMiddleware_)).setWstethMockedPrice(
                        initialWSTETHMockedPrice
                    );
                }
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
        returns (LiquidationRewardsManagerWstEth liquidationRewardsManager_)
    {
        address liquidationRewardsManagerAddress = vm.envOr("LIQUIDATION_REWARDS_MANAGER_ADDRESS", address(0));

        if (liquidationRewardsManagerAddress != address(0)) {
            liquidationRewardsManager_ = LiquidationRewardsManagerWstEth(liquidationRewardsManagerAddress);
        } else {
            liquidationRewardsManager_ = new LiquidationRewardsManagerWstEth(IWstETH(wstETHAddress));
        }
    }

    /**
     * @notice Deploy the USDN token and the WUSDN token
     * @dev Will return the already deployed ones if an address is in the env variables
     * On mainnet the `WUSDN_ADDRESS` env variable is required
     * @return usdn_ The deployed Usdn contract
     * @return wusdn_ The deployed Wusdn contract
     */
    function _deployUsdnAndWusdn() internal returns (Usdn usdn_, Wusdn wusdn_) {
        address usdnAddress = payable(vm.envOr("USDN_ADDRESS", address(0)));
        address wusdnAddress = payable(vm.envOr("WUSDN_ADDRESS", address(0)));

        if (usdnAddress != address(0)) {
            usdn_ = Usdn(usdnAddress);
        } else {
            if (_isProdEnv) {
                usdn_ = Usdn(USDN_MAINNET);
            } else {
                usdn_ = new Usdn(address(0), address(0));
            }
        }

        if (wusdnAddress != address(0)) {
            wusdn_ = Wusdn(wusdnAddress);
        } else {
            if (_isProdEnv) {
                wusdn_ = Wusdn(WUSDN_MAINNET);
            } else {
                wusdn_ = new Wusdn(usdn_);
            }
        }
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
    function _initializeUsdnProtocolFork(
        IUsdnProtocol usdnProtocol,
        WstETH wstETH,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        Usdn usdn,
        Rebalancer rebalancer
    ) internal {
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, _deployerAddress);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, _deployerAddress);

        usdnProtocol.setRebalancer(rebalancer);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));

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
     * @param rebalancer The rebalancer
     */
    function _handlePostDeployment(
        IUsdnProtocol usdnProtocol,
        Rebalancer rebalancer,
        WstEthOracleMiddleware wstEthOracleMiddleware,
        LiquidationRewardsManagerWstEth liquidationRewardsManager
    ) internal {
        // grant the necessary roles to the deployer to set the rebalancer and then revoke them
        bytes32 ADMIN_SET_EXTERNAL_ROLE = Constants.ADMIN_SET_EXTERNAL_ROLE;
        bytes32 SET_EXTERNAL_ROLE = Constants.SET_EXTERNAL_ROLE;
        bytes32 MIDDLEWARE_ADMIN_ROLE = wstEthOracleMiddleware.ADMIN_ROLE();

        usdnProtocol.grantRole(ADMIN_SET_EXTERNAL_ROLE, _deployerAddress);
        usdnProtocol.grantRole(SET_EXTERNAL_ROLE, _deployerAddress);

        usdnProtocol.setRebalancer(rebalancer);

        usdnProtocol.revokeRole(SET_EXTERNAL_ROLE, _deployerAddress);
        usdnProtocol.revokeRole(ADMIN_SET_EXTERNAL_ROLE, _deployerAddress);
        wstEthOracleMiddleware.revokeRole(MIDDLEWARE_ADMIN_ROLE, _deployerAddress);

        // transfer the ownership of the contracts to the safe address
        usdnProtocol.beginDefaultAdminTransfer(_safeAddress);
        wstEthOracleMiddleware.beginDefaultAdminTransfer(_safeAddress);
        liquidationRewardsManager.transferOwnership(_safeAddress);
        rebalancer.transferOwnership(_safeAddress);
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
        // mandatory env variables : DEPLOYER_ADDRESS and IS_PROD_ENV
        try vm.envAddress("DEPLOYER_ADDRESS") returns (address deployerAddress_) {
            _deployerAddress = deployerAddress_;
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        try vm.envBool("IS_PROD_ENV") returns (bool isProdEnv_) {
            _isProdEnv = isProdEnv_;
        } catch {
            revert("IS_PROD_ENV is required");
        }

        if (_isProdEnv) {
            try vm.envAddress("SAFE_ADDRESS") returns (address safeAddress_) {
                _safeAddress = safeAddress_;
            } catch {
                revert("SAFE_ADDRESS is required");
            }
            _feeCollector = vm.envOr("FEE_COLLECTOR", _safeAddress);
        } else {
            try vm.envUint("INIT_LONG_AMOUNT") returns (uint256 initLongAmount_) {
                _longAmount = initLongAmount_;
            } catch {
                revert("INIT_LONG_AMOUNT is required");
            }
            _feeCollector = vm.envOr("FEE_COLLECTOR", _deployerAddress);
        }

        string memory etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string("XXXXXXXXXXXXXXXXX"));
        vm.setEnv("ETHERSCAN_API_KEY", etherscanApiKey);
    }
}
