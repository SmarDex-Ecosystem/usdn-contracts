// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Sdex } from "../../test/utils/Sdex.sol";
import { Utils } from "../utils/Utils.s.sol";

import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

abstract contract DeployUsdnProtocol is Script {
    Sdex constant SDEX = Sdex(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);

    Types.Storage internal _storage;
    Utils internal _utils = new Utils();

    /**
     * @notice Deploy the USDN protocol.
     * @param initStorage The storage initialization parameters.
     * @return usdnProtocol_ The USDN protocol proxy.
     */
    function _deployProtocol(Types.InitStorage storage initStorage) internal returns (IUsdnProtocol usdnProtocol_) {
        // internal validation of the Usdn protocol
        _utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        // clean and build contracts for openzeppelin module
        _utils.cleanAndBuildContracts();

        // we need to allow external library linking and immutable variables in the openzeppelin module
        Options memory opts;
        opts.unsafeAllow = "external-library-linking,state-variable-immutable";

        vm.startBroadcast();

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        _storage._protocolFallbackAddr = address(protocolFallback);

        address proxy = Upgrades.deployUUPSProxy(
            "UsdnProtocolImpl.sol", abi.encodeCall(UsdnProtocolImpl.initializeStorage, (initStorage)), opts
        );

        vm.stopBroadcast();

        usdnProtocol_ = IUsdnProtocol(proxy);
    }
}
