// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {
    UniswapImmutables,
    UniswapParameters
} from "@uniswap/universal-router/contracts/modules/uniswap/UniswapImmutables.sol";
import {
    PaymentsImmutables, PaymentsParameters
} from "@uniswap/universal-router/contracts/modules/PaymentsImmutables.sol";

import { Dispatcher } from "src/UniversalRouter/base/Dispatcher.sol";
import { IUniversalRouter } from "src/UniversalRouter/interfaces/IUniversalRouter.sol";
import { RouterParameters } from "src/UniversalRouter/base/RouterImmutables.sol";
import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

import { UsdnImmutables, UsdnParameters } from "src/UniversalRouter/modules/usdn/UsdnImmutables.sol";

contract UniversalRouter is IUniversalRouter, Dispatcher {
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionDeadlinePassed();
        _;
    }

    constructor(RouterParameters memory params)
        UniswapImmutables(
            UniswapParameters(params.v2Factory, params.v3Factory, params.pairInitCodeHash, params.poolInitCodeHash)
        )
        PaymentsImmutables(PaymentsParameters(params.permit2, params.weth9, address(0), address(0)))
        UsdnImmutables(UsdnParameters(params.usdn, params.wusdn, params.usdnProtocol))
    { }

    /// @inheritdoc IUniversalRouter
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline)
        external
        payable
        checkDeadline(deadline)
    {
        execute(commands, inputs);
    }

    /// @inheritdoc Dispatcher
    function execute(bytes calldata commands, bytes[] calldata inputs) public payable override isNotLocked {
        bool success;
        bytes memory output;
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) {
            revert LengthMismatch();
        }

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex = 0; commandIndex < numCommands;) {
            bytes1 command = commands[commandIndex];

            bytes calldata input = inputs[commandIndex];

            (success, output) = dispatch(command, input);

            if (!success && successRequired(command)) {
                revert ExecutionFailed({ commandIndex: commandIndex, message: output });
            }

            unchecked {
                commandIndex++;
            }
        }
    }

    function successRequired(bytes1 command) internal pure returns (bool) {
        return command & Commands.FLAG_ALLOW_REVERT == 0;
    }

    /// @notice To receive ETH from WETH
    receive() external payable { }
}
