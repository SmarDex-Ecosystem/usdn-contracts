// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Sdex } from "../../test/utils/Sdex.sol";
import { Utils } from "../utils/Utils.s.sol";

import { LiquidationRewardsManager } from "../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IOracleMiddleware } from "../../src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

abstract contract DeployProtocolProd is Script {
    Sdex constant SDEX = Sdex(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);

    Utils internal _utils = new Utils();

    /**
     * @notice Deploy the USDN ecosystem
     * @param liquidationRewardsManager The liquidation rewards manager
     * @param oracleMiddleware The oracle middleware
     * @param underlying The underlying token contract
     * @return Rebalancer_ The rebalancer
     * @return UsdnProtocol_ The USDN protocol proxy
     * @return Usdn_ The USDN token contract
     * @return Wusdn_ The WUSDN token contract
     */
    function _deploy(
        LiquidationRewardsManager liquidationRewardsManager,
        IOracleMiddleware oracleMiddleware,
        IERC20Metadata underlying
    ) internal returns (Rebalancer Rebalancer_, IUsdnProtocol UsdnProtocol_, Usdn Usdn_, Wusdn Wusdn_) {
        // internal validation of the Usdn protocol
        _utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        vm.startBroadcast();
        Usdn_ = new Usdn(address(0), address(0));
        Wusdn_ = new Wusdn(Usdn_);
        vm.stopBroadcast();

        UsdnProtocol_ = _deployProtocol(oracleMiddleware, liquidationRewardsManager, underlying, Usdn_);

        vm.startBroadcast();
        Rebalancer_ = new Rebalancer(UsdnProtocol_);
        vm.stopBroadcast();

        return (Rebalancer_, UsdnProtocol_, Usdn_, Wusdn_);
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

        vm.startBroadcast();

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        address proxy = Upgrades.deployUUPSProxy(
            "UsdnProtocolImpl.sol",
            abi.encodeCall(
                UsdnProtocolImpl.initializeStorage,
                (usdn, SDEX, underlying, oracleMiddleware, liquidationRewardsManager, 100, msg.sender, protocolFallback)
            ),
            opts
        );

        vm.stopBroadcast();

        usdnProtocol_ = IUsdnProtocol(proxy);
    }
}
