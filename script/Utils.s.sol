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
        success = _runCommand(inputs);
        if (!success) {
            revert("function clash detected, run the functionClashes.ts script to see the clashing functions");
        }
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

    /**
     * @notice Function to run an external command with ffi
     * @param inputs The command to run
     * @return success True if the command was successful, false otherwise
     */
    function _runCommand(string[] memory inputs) internal returns (bool success) {
        bytes memory result = vm.ffi(inputs);
        return (result.length == 0);
    }
}
