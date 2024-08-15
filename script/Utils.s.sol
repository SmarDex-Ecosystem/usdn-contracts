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
    function validateProtocol() public {
        string[] memory inputs = _buildCommandFunctionClashes();
        try this.runFfiCommand(inputs) { }
        catch {
            revert("function clash detected, run the functionClashes.ts script to see the clashing functions");
        }
    }

    /**
     * @notice Get the amount of stEth for one wstEth on mainnet
     * @return stEthPerToken_ The amount of stEth for 1 wstEth
     */
    function getStEthPerTokenMainnet() public returns (uint256 stEthPerToken_) {
        string[] memory inputs = new string[](6);
        inputs[0] = "cast";
        inputs[1] = "call";
        inputs[2] = "-r";
        inputs[3] = "https://ethereum-rpc.publicnode.com";
        inputs[4] = "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0";
        inputs[5] = "stEthPerToken()";

        bytes memory result = runFfiCommand(inputs);
        stEthPerToken_ = abi.decode(result, (uint256));
    }

    /**
     * @notice Clean the `out` directory and build the contracts
     * @dev Call this function to clean the `out` directory and build the contracts
     */
    function cleanAndBuildContracts() external {
        _cleanOutDir();
        _buildContracts();
    }

    /**
     * @notice Function to run an external command with ffi
     * @dev This function reverts if the command fails
     * @param inputs The command to run
     * @return The result of the command, printed to stdout
     */
    function runFfiCommand(string[] memory inputs) public returns (bytes memory) {
        Vm.FfiResult memory result = vm.tryFfi(inputs);

        if (result.exitCode != 0) {
            revert(string(abi.encodePacked('Failed to run bash command with "', inputs[0], '": ', result.stderr)));
        } else {
            return (result.stdout);
        }
    }

    /**
     * @notice Clean the `out` directory
     * @dev Call this function to clean the `out` directory
     */
    function _cleanOutDir() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "forge";
        inputs[1] = "clean";
        runFfiCommand(inputs);
    }

    /**
     * @notice Build the contracts
     * @dev Call this function to build the contracts
     */
    function _buildContracts() internal {
        string[] memory inputs = new string[](5);
        inputs[0] = "forge";
        inputs[1] = "build";
        inputs[2] = "--via-ir";
        inputs[3] = "--skip";
        inputs[4] = "test";
        runFfiCommand(inputs);
    }

    /**
     * @notice Build the command to run the functionClashes.ts script
     * @return inputs_ The command to run the functionClashes.ts script
     */
    function _buildCommandFunctionClashes() internal pure returns (string[] memory inputs_) {
        inputs_ = new string[](7);
        uint8 i = 0;

        // create the command to run the functionClashes.ts script
        // npx ts-node UsdnProtocolImpl.sol UsdnProtocolFallback.sol -s UsdnProtocolStorage.sol
        inputs_[i++] = "npx";
        inputs_[i++] = "ts-node";
        inputs_[i++] = SCRIPT_PATH;
        inputs_[i++] = "UsdnProtocolImpl.sol";
        inputs_[i++] = "UsdnProtocolFallback.sol";
        // we need to give the storage contract to remove common functions
        inputs_[i++] = "-s";
        inputs_[i++] = "UsdnProtocolStorage.sol";
    }
}
