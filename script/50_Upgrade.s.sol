// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { Utils } from "./Utils.s.sol";

import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract Upgrade is Script {
    Utils _utils = new Utils();
    address _deployerAddress;
    IUsdnProtocol _usdnProtocol;

    function run() external {
        // Check and save the required environment variables
        _handleEnvVariables();

        // Make sure the address used has the permission to upgrade the protocol
        require(
            _usdnProtocol.hasRole(_usdnProtocol.PROXY_UPGRADE_ROLE(), _deployerAddress),
            "DEPLOYER_ADDRESS does not have the permission to upgrade the protocol"
        );

        // clean and build contracts for openzeppelin module
        _utils.cleanAndBuildContracts();

        // validate the Usdn protocol before deploying it
        _utils.validateProtocol("UsdnProtocolImpl.sol", "UsdnProtocolFallback.sol");

        vm.startBroadcast(_deployerAddress);

        // we need to allow external library linking for the openzeppelin module
        Options memory opts;
        opts.unsafeAllow = "external-library-linking,state-variable-immutable";
        opts.referenceContract = "UsdnProtocolImpl.sol";

        // deploy the new fallback contract
        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();

        Upgrades.upgradeProxy(
            address(_usdnProtocol),
            "UsdnProtocolImpl.sol",
            // call the initialize function of the new implementation to upgrade the fallback contract
            // if this function does not exist, you will need to implement it
            // IMPORTANT: It is mandatory to add a call here, otherwise the transaction will revert
            // the Solady implementation does not allow us to upgrade without calling a function afterwards
            abi.encodeWithSignature("initializeStorageV2(address)", (address(protocolFallback))),
            opts
        );

        vm.stopBroadcast();
    }

    /// @notice Handle the environment variables
    function _handleEnvVariables() internal {
        try vm.envAddress("DEPLOYER_ADDRESS") {
            _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        } catch {
            revert("DEPLOYER_ADDRESS is required");
        }

        try vm.envAddress("USDN_PROTOCOL") {
            _usdnProtocol = IUsdnProtocol(vm.envAddress("USDN_PROTOCOL"));
        } catch {
            revert("USDN_PROTOCOL is required, otherwise launch 01_Deploy");
        }

        string memory etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string("XXXXXXXXXXXXXXXXX"));
        vm.setEnv("ETHERSCAN_API_KEY", etherscanApiKey);
    }
}
