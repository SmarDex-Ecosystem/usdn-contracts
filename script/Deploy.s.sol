// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";
import { Contract } from "src/Contract.sol";

/**
 * @title DeployScript
 * @dev This script is a deploy script template that create a new Contract instance.
 * NOTE: This script should be run with `make deploy` command.
 */
contract DeployScript is Script {
    function run() external returns (Contract instance) {
        // Fetch the deployer's private key from the environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Use the deployer's private key to sign following transactions
        vm.startBroadcast(deployerPrivateKey);

        // Create a new Contract
        instance = new Contract();

        // Stop using the deployer's private key
        vm.stopBroadcast();
    }
}
