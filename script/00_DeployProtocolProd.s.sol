// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";
import { Utils } from "./utils/Utils.s.sol";

import { LiquidationRewardsManager } from "../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IOracleMiddleware } from "../src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

abstract contract DeployProtocolProd is Script {
    Sdex constant SDEX = Sdex(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);
    address internal _deployerAddress;
    address internal _feeCollector;
    address internal _safeAddress;
    Utils internal _utils = new Utils();

    /**
     * @notice Deploy the USDN ecosystem
     * @param liquidationRewardsManager The liquidation rewards manager
     * @param oracleMiddleware The oracle middleware
     * @param underlying The underlying token contract
     * @param usdn The USDN token contract
     * @return Rebalancer_ The rebalancer
     * @return UsdnProtocol_ The USDN protocol proxy
     */
    function _deploy(
        LiquidationRewardsManager liquidationRewardsManager,
        IOracleMiddleware oracleMiddleware,
        IERC20Metadata underlying,
        Usdn usdn
    ) internal returns (Rebalancer Rebalancer_, IUsdnProtocol UsdnProtocol_) {
        _handleEnvVariables();

        // internal validation of the Usdn protocol
        _utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        vm.startBroadcast(_deployerAddress);

        // we need to stop the broadcast before the OZ validation of the Usdn protocol
        vm.stopBroadcast();

        UsdnProtocol_ = _deployProtocol(oracleMiddleware, liquidationRewardsManager, underlying, usdn);

        vm.startBroadcast(_deployerAddress);

        Rebalancer_ = new Rebalancer(UsdnProtocol_);

        _handlePostDeployment(UsdnProtocol_, Rebalancer_, oracleMiddleware, liquidationRewardsManager);

        vm.stopBroadcast();

        return (Rebalancer_, UsdnProtocol_);
    }

    /**
     * @notice Deploy the USDN protocol
     * @param oracleMiddleware The oracle middleware
     * @param liquidationRewardsManager The liquidation rewards manager
     * @return usdnProtocol_ The deployed protocol
     */
    function _deployProtocol(
        IOracleMiddleware oracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager,
        IERC20Metadata underlying,
        Usdn usdn
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
                    SDEX,
                    underlying,
                    oracleMiddleware,
                    liquidationRewardsManager,
                    100,
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
     * @notice Handle post-deployment tasks
     * @param usdnProtocol The USDN protocol
     * @param rebalancer The rebalancer
     */
    function _handlePostDeployment(
        IUsdnProtocol usdnProtocol,
        Rebalancer rebalancer,
        IOracleMiddleware wstEthOracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager
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

    /// @notice Handle the environment variables
    function _handleEnvVariables() internal {
        // mandatory env variables : DEPLOYER_ADDRESS and SAFE_ADDRESS
        try vm.envAddress("DEPLOYER_ADDRESS") returns (address deployerAddress_) {
            _deployerAddress = deployerAddress_;
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        try vm.envAddress("SAFE_ADDRESS") returns (address safeAddress_) {
            _safeAddress = safeAddress_;
        } catch {
            revert("SAFE_ADDRESS is required");
        }

        _feeCollector = vm.envOr("FEE_COLLECTOR", _safeAddress);
    }
}
