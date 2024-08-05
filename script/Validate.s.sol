// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";

contract Validate is Script {
    struct Options {
        bool debug;
        bool sameName;
    }

    string constant SCRIPT_PATH = "script/functionClashes.ts";

    function run() external {
        validateProtocol(Options(true, true));
    }

    function validateProtocol(Options memory opts) public {
        string[] memory inputs = _buildCommandFunctionClashes(opts);
        bool success = _runCommand(inputs);
        if (!success) {
            revert("function clach detected, run the functionClashes.ts script to see the clashing functions");
        }
    }

    function _buildCommandFunctionClashes(Options memory opts) internal pure returns (string[] memory inputs) {
        string[] memory inputBuilder = new string[](7);
        uint8 i = 0;

        inputBuilder[i++] = "npx";
        inputBuilder[i++] = "ts-node";
        inputBuilder[i++] = SCRIPT_PATH;
        // TO DO : find a way to automate this
        inputBuilder[i++] = "UsdnProtocolImpl.sol";
        inputBuilder[i++] = "UsdnProtocolFallback.sol";

        if (opts.sameName) {
            inputBuilder[i++] = "--same-name";
        }

        if (opts.debug) {
            inputBuilder[i++] = "--debug";
        }

        // Create a copy inputs with the correct length
        inputs = new string[](i);
        for (uint8 j = 0; j < i; j++) {
            inputs[j] = inputBuilder[j];
        }
    }

    function _runCommand(string[] memory inputs) internal returns (bool success) {
        bytes memory result = vm.ffi(inputs);
        if (result.length == 0) {
            return true;
        } else {
            return false;
        }
    }
}
