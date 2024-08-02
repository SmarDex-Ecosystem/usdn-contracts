// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";

contract Validate is Script {
    struct Options {
        bool debug;
        bool sameName;
    }

    function run() external {
        string[] memory inputs = _buildCommandFunctionClashes(Options(false, true));
        _runCommand(inputs);
    }

    function validateProtocol(Options memory opts) external {
        string[] memory inputs = _buildCommandFunctionClashes(opts);
        _runCommand(inputs);
    }

    function _buildCommandFunctionClashes(Options memory opts) internal pure returns (string[] memory inputs) {
        string[] memory inputBuilder = new string[](6);
        uint8 i = 0;

        inputBuilder[i++] = "ts-node";
        inputBuilder[i++] = "script/functionClashes.ts";
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

    function _runCommand(string[] memory inputs) internal {
        bytes memory result = vm.ffi(inputs);
        if (result.length == 0) { } else {
            // string memory output = abi.decode(result, (string));
            // console2.log(output);
            revert("Error in functionClashes.ts");
        }
    }
}
