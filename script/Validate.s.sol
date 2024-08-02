// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";

contract Deploy is Script {
    struct Options {
        bool debug;
        bool sameName;
    }

    function run() external {
        buildCommandFunctionClashes(Options(false, false));
    }

    function buildCommandFunctionClashes(Options memory opts) internal {
        string[] memory inputBuilder = new string[](10);

        uint8 i = 0;

        inputBuilder[i++] = "bash ts-node script/functionClashes.ts UsdnProtocolImpl.sol UsdnProtocolFallback.sol";

        if (opts.sameName) {
            inputBuilder[i++] = "--same-name";
        }

        if (opts.debug) {
            inputBuilder[i++] = "--debug";
        }

        // Create a copy of inputs but with the correct length
        string[] memory inputs = new string[](i);
        for (uint8 j = 0; j < i; j++) {
            inputs[j] = inputBuilder[j];
        }

        // string memory commandString;

        // for (uint256 z = 0; i < inputs.length; i++) {
        //     commandString = string(abi.encodePacked(commandString, inputs[i]));
        //     if (i != inputs.length - 1) {
        //         commandString = string(abi.encodePacked(commandString, " "));
        //     }
        // }
        string[] memory inputs2 = new string[](1);
        inputs2[0] = "echo lol";
        bytes memory result = vm.ffi(inputs2);
        console2.logBytes(result);
        // Vm.FfiResult memory result = vm.tryFfi(inputs);
        // if (result.exitCode != 0 && result.stdout.length == 0 && result.stderr.length == 0) {
        //     revert(string(abi.encodePacked('Failed to run bash command with "', inputs[0])));
        // } else {
        //     // return result;
        // }
    }
}
