// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Utils } from "./utils/Utils.s.sol";

import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract Upgrade is Script {
    address _deployerAddress;
    IUsdnProtocol _usdnProtocol;

    function run() external returns (UsdnProtocolImpl newUsdnProtocolImpl_) {
        _handleEnvVariables();

        vm.startBroadcast(_deployerAddress);
        _usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, _deployerAddress);
        _usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, _deployerAddress);

        bytes32 oldImpl =
            vm.load(address(_usdnProtocol), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

        require(
            _usdnProtocol.hasRole(Constants.PROXY_UPGRADE_ROLE, _deployerAddress),
            "DEPLOYER_ADDRESS does not have the permission to upgrade the protocol"
        );

        newUsdnProtocolImpl_ = new UsdnProtocolImpl();
        _usdnProtocol.upgradeToAndCall(address(newUsdnProtocolImpl_), "");

        bytes32 newImpl =
            vm.load(address(_usdnProtocol), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

        require(oldImpl != newImpl, "Upgrade failed");
        require(address(uint160(uint256(newImpl))) == address(newUsdnProtocolImpl_), "Upgrade failed");

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
