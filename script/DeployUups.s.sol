// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Vm } from "forge-std/Vm.sol";
import { Options, UnsafeUpgrades, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";

import { LiquidationRewardsManager } from "../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../src/UsdnProtocol/UsdnProtocol.sol";
import { UsdnProtocolSetters } from "../src/UsdnProtocol/UsdnProtocolSetters.sol";
import { IBaseLiquidationRewardsManager } from "../src/interfaces/OracleMiddleware/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IUsdn } from "../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

library DeployUups {
    /**
     * @notice Deploy the USDN Protocol
     * @return UsdnProtocol_ The USDN protocol
     */
    function deploy(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        IBaseLiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Types.Roles memory roles,
        Options memory opts
    ) external returns (IUsdnProtocol UsdnProtocol_) {
        address proxy = Upgrades.deployUUPSProxy(
            "UsdnProtocol.sol",
            abi.encodeCall(
                UsdnProtocol.initializeStorage,
                (usdn, sdex, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector, roles)
            ),
            opts
        );
        UsdnProtocol_ = IUsdnProtocol(proxy);
        UsdnProtocolSetters protocolSetters = new UsdnProtocolSetters();
        UsdnProtocol_.setSettersContract(address(protocolSetters));
    }

    function deployUnsafe(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        IBaseLiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Types.Roles memory roles
    ) public returns (IUsdnProtocol UsdnProtocol_) {
        UsdnProtocol implementation = new UsdnProtocol();
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation),
            abi.encodeCall(
                UsdnProtocol.initializeStorage,
                (usdn, sdex, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector, roles)
            )
        );
        UsdnProtocol_ = IUsdnProtocol(proxy);
        UsdnProtocolSetters protocolSetters = new UsdnProtocolSetters();
        UsdnProtocol_.setSettersContract(address(protocolSetters));
    }
}
