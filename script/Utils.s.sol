// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";

contract Utils is Script {
    string constant SCRIPT_PATH = "script/functionClashes.ts";

    // to run the script in standalone mode
    function run() external {
        validateProtocol();
    }

    /**
     * @notice Validate the Usdn protocol
     * @dev Call this function to validate the Usdn protocol before deploying it
     */
    function validateProtocol() public returns (bool success) {
        string[] memory inputs = _buildCommandFunctionClashes();
        try this.runFfiCommand(inputs) {
            return true;
        } catch {
            revert("function clash detected, run the functionClashes.ts script to see the clashing functions");
        }
    }

    function cleanAndBuildContracts() external {
        _cleanOutDir();
        _buildContracts();
    }

    /**
     * @notice Function to run an external command with ffi
     * @dev This function revert if the command fails
     * @param inputs The command to run
     * @return The result of the command, printed to stdout
     */
    function runFfiCommand(string[] memory inputs) public returns (bytes memory) {
        Vm.FfiResult memory result = vm.tryFfi(inputs);

        if (result.exitCode != 0 && result.stdout.length == 0 && result.stderr.length == 0) {
            revert(string(abi.encodePacked('Failed to run bash command with "', inputs[0], '": ', result.stderr)));
        } else {
            return (result.stdout);
        }
    }

    function _cleanOutDir() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "forge";
        inputs[1] = "clean";
        runFfiCommand(inputs);
    }

    function _buildContracts() internal {
        string[] memory inputs = new string[](4);
        inputs[0] = "forge";
        inputs[1] = "build";
        inputs[2] = "--skip";
        inputs[3] = "test";
        runFfiCommand(inputs);
    }

    /**
     * @notice Build the command to run the functionClashes.ts script
     * @return inputs The command to run the functionClashes.ts script
     */
    function _buildCommandFunctionClashes() internal pure returns (string[] memory inputs) {
        inputs = new string[](7);
        uint8 i = 0;

        // create the command to run the functionClashes.ts script
        // npx ts-node UsdnProtocolImpl.sol UsdnProtocolFallback.sol -s UsdnProtocolStorage.sol
        inputs[i++] = "npx";
        inputs[i++] = "ts-node";
        inputs[i++] = SCRIPT_PATH;
        inputs[i++] = "UsdnProtocolImpl.sol";
        inputs[i++] = "UsdnProtocolFallback.sol";
        // we need to give the storage contract to remove common functions
        inputs[i++] = "-s";
        inputs[i++] = "UsdnProtocolStorage.sol";
    }
}
