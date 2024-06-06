// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { LockAndMsgSender } from "@uniswap/universal-router/contracts/base/LockAndMsgSender.sol";
import { Payments } from "@uniswap/universal-router/contracts/modules/Payments.sol";
import { BytesLib } from "@uniswap/universal-router/contracts/modules/uniswap/v3/BytesLib.sol";
import { V3SwapRouter } from "@uniswap/universal-router/contracts/modules/uniswap/v3/V3SwapRouter.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { V2SwapRouter } from "src/UniversalRouter/modules/uniswap/v2/V2SwapRouter.sol";
import { UsdnProtocolRouter } from "src/UniversalRouter/modules/usdn/UsdnProtocolRouter.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { LidoRouter } from "src/UniversalRouter/modules/lido/LidoRouter.sol";

/**
 * @title Decodes and Executes Commands
 * @notice Called by the UniversalRouter contract to efficiently decode and execute a singular command
 */
abstract contract Dispatcher is
    Payments,
    V2SwapRouter,
    V3SwapRouter,
    UsdnProtocolRouter,
    LidoRouter,
    LockAndMsgSender
{
    using BytesLib for bytes;

    /**
     * @notice Indicates that the command type is invalid
     * @param commandType The command type
     */
    error InvalidCommandType(uint256 commandType);

    /**
     * @notice Decodes and executes the given command with the given inputs
     * @dev 2 masks are used to enable use of a nested-if statement in execution for efficiency reasons
     * @param commandType The command type to execute
     * @param inputs The inputs to execute the command with
     * @return success_ True on success of the command, false on failure
     * @return output_ The outputs or error messages, if any, from the command
     */
    function dispatch(bytes1 commandType, bytes calldata inputs)
        internal
        returns (bool success_, bytes memory output_)
    {
        // TODO CHECK IF USEFUL
        output_ = "";
        uint256 command = uint8(commandType & Commands.COMMAND_TYPE_MASK);

        success_ = true;

        if (command < Commands.FOURTH_IF_BOUNDARY) {
            if (command < Commands.THIRD_IF_BOUNDARY) {
                if (command < Commands.SECOND_IF_BOUNDARY) {
                    if (command < Commands.FIRST_IF_BOUNDARY) {
                        if (command == Commands.V3_SWAP_EXACT_IN) {
                            // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                            address recipient;
                            uint256 amountIn;
                            uint256 amountOutMin;
                            bool payerIsUser;
                            assembly {
                                recipient := calldataload(inputs.offset)
                                amountIn := calldataload(add(inputs.offset, 0x20))
                                amountOutMin := calldataload(add(inputs.offset, 0x40))
                                // 0x60 offset is the path, decoded below
                                payerIsUser := calldataload(add(inputs.offset, 0x80))
                            }
                            bytes calldata path = inputs.toBytes(3);
                            address payer = payerIsUser ? lockedBy : address(this);
                            v3SwapExactInput(map(recipient), amountIn, amountOutMin, path, payer);
                        } else if (command == Commands.V3_SWAP_EXACT_OUT) {
                            // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                            address recipient;
                            uint256 amountOut;
                            uint256 amountInMax;
                            bool payerIsUser;
                            assembly {
                                recipient := calldataload(inputs.offset)
                                amountOut := calldataload(add(inputs.offset, 0x20))
                                amountInMax := calldataload(add(inputs.offset, 0x40))
                                // 0x60 offset is the path, decoded below
                                payerIsUser := calldataload(add(inputs.offset, 0x80))
                            }
                            bytes calldata path = inputs.toBytes(3);
                            address payer = payerIsUser ? lockedBy : address(this);
                            v3SwapExactOutput(map(recipient), amountOut, amountInMax, path, payer);
                        } else if (command == Commands.PERMIT2_TRANSFER_FROM) {
                            // equivalent: abi.decode(inputs, (address, address, uint160))
                            address token;
                            address recipient;
                            uint160 amount;
                            assembly {
                                token := calldataload(inputs.offset)
                                recipient := calldataload(add(inputs.offset, 0x20))
                                amount := calldataload(add(inputs.offset, 0x40))
                            }
                            permit2TransferFrom(token, lockedBy, map(recipient), amount);
                        } else if (command == Commands.PERMIT2_PERMIT_BATCH) {
                            (IAllowanceTransfer.PermitBatch memory permitBatch,) =
                                abi.decode(inputs, (IAllowanceTransfer.PermitBatch, bytes));
                            bytes calldata data = inputs.toBytes(1);
                            PERMIT2.permit(lockedBy, permitBatch, data);
                        } else if (command == Commands.SWEEP) {
                            // equivalent:  abi.decode(inputs, (address, address, uint256))
                            address token;
                            address recipient;
                            uint160 amountMin;
                            assembly {
                                token := calldataload(inputs.offset)
                                recipient := calldataload(add(inputs.offset, 0x20))
                                amountMin := calldataload(add(inputs.offset, 0x40))
                            }
                            Payments.sweep(token, map(recipient), amountMin);
                        } else if (command == Commands.TRANSFER) {
                            // equivalent:  abi.decode(inputs, (address, address, uint256))
                            address token;
                            address recipient;
                            uint256 value;
                            assembly {
                                token := calldataload(inputs.offset)
                                recipient := calldataload(add(inputs.offset, 0x20))
                                value := calldataload(add(inputs.offset, 0x40))
                            }
                            Payments.pay(token, map(recipient), value);
                        } else if (command == Commands.PAY_PORTION) {
                            // equivalent:  abi.decode(inputs, (address, address, uint256))
                            address token;
                            address recipient;
                            uint256 bips;
                            assembly {
                                token := calldataload(inputs.offset)
                                recipient := calldataload(add(inputs.offset, 0x20))
                                bips := calldataload(add(inputs.offset, 0x40))
                            }
                            Payments.payPortion(token, map(recipient), bips);
                        } else {
                            revert InvalidCommandType(command);
                        }
                    } else {
                        if (command == Commands.V2_SWAP_EXACT_IN) {
                            // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                            address recipient;
                            uint256 amountIn;
                            uint256 amountOutMin;
                            bool payerIsUser;
                            assembly {
                                recipient := calldataload(inputs.offset)
                                amountIn := calldataload(add(inputs.offset, 0x20))
                                amountOutMin := calldataload(add(inputs.offset, 0x40))
                                // 0x60 offset is the path, decoded below
                                payerIsUser := calldataload(add(inputs.offset, 0x80))
                            }
                            address[] calldata path = inputs.toAddressArray(3);
                            address payer = payerIsUser ? lockedBy : address(this);
                            v2SwapExactInput(map(recipient), amountIn, amountOutMin, path, payer);
                        } else if (command == Commands.V2_SWAP_EXACT_OUT) {
                            // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                            address recipient;
                            uint256 amountOut;
                            uint256 amountInMax;
                            bool payerIsUser;
                            assembly {
                                recipient := calldataload(inputs.offset)
                                amountOut := calldataload(add(inputs.offset, 0x20))
                                amountInMax := calldataload(add(inputs.offset, 0x40))
                                // 0x60 offset is the path, decoded below
                                payerIsUser := calldataload(add(inputs.offset, 0x80))
                            }
                            address[] calldata path = inputs.toAddressArray(3);
                            address payer = payerIsUser ? lockedBy : address(this);
                            v2SwapExactOutput(map(recipient), amountOut, amountInMax, path, payer);
                        } else if (command == Commands.PERMIT2_PERMIT) {
                            // equivalent: abi.decode(inputs, (IAllowanceTransfer.PermitSingle, bytes))
                            IAllowanceTransfer.PermitSingle calldata permitSingle;
                            assembly {
                                permitSingle := inputs.offset
                            }
                            bytes calldata data = inputs.toBytes(6); // permitSingle takes first 6 slots (0..5)
                            PERMIT2.permit(lockedBy, permitSingle, data);
                        } else if (command == Commands.WRAP_ETH) {
                            // equivalent: abi.decode(inputs, (address, uint256))
                            address recipient;
                            uint256 amountMin;
                            assembly {
                                recipient := calldataload(inputs.offset)
                                amountMin := calldataload(add(inputs.offset, 0x20))
                            }
                            Payments.wrapETH(map(recipient), amountMin);
                        } else if (command == Commands.UNWRAP_WETH) {
                            // equivalent: abi.decode(inputs, (address, uint256))
                            address recipient;
                            uint256 amountMin;
                            assembly {
                                recipient := calldataload(inputs.offset)
                                amountMin := calldataload(add(inputs.offset, 0x20))
                            }
                            Payments.unwrapWETH9(map(recipient), amountMin);
                        } else if (command == Commands.PERMIT2_TRANSFER_FROM_BATCH) {
                            // TODO PERMIT2_TRANSFER_FROM_BATCH
                        } else {
                            revert InvalidCommandType(command);
                        }
                    }
                } else {
                    // comment for the eights actions(INITIATE and VALIDATE) of the USDN protocol
                    // we don't allow the transaction to revert if the actions was not successful (due to pending
                    // liquidations), so we ignore the success boolean. This is because it's important to perform
                    // liquidations if they are needed, and it would be a big waste of gas for the user to revert
                    if (command == Commands.INITIATE_DEPOSIT) {
                        (
                            uint256 amount,
                            address to,
                            address validator,
                            bytes memory currentPriceData,
                            PreviousActionsData memory previousActionsData,
                            uint256 ethAmount
                        ) = abi.decode(inputs, (uint256, address, address, bytes, PreviousActionsData, uint256));
                        _usdnInitiateDeposit(
                            amount, map(to), map(validator), currentPriceData, previousActionsData, ethAmount
                        );
                    } else if (command == Commands.INITIATE_WITHDRAWAL) {
                        (
                            uint256 usdnShares,
                            address to,
                            address validator,
                            bytes memory currentPriceData,
                            PreviousActionsData memory previousActionsData,
                            uint256 ethAmount
                        ) = abi.decode(inputs, (uint256, address, address, bytes, PreviousActionsData, uint256));
                        _usdnInitiateWithdrawal(
                            usdnShares, map(to), map(validator), currentPriceData, previousActionsData, ethAmount
                        );
                    } else if (command == Commands.INITIATE_OPEN) {
                        (
                            uint256 amount,
                            uint128 desiredLiqPrice,
                            address to,
                            address validator,
                            bytes memory currentPriceData,
                            PreviousActionsData memory previousActionsData,
                            uint256 ethAmount
                        ) = abi.decode(
                            inputs, (uint256, uint128, address, address, bytes, PreviousActionsData, uint256)
                        );
                        _usdnInitiateOpenPosition(
                            amount,
                            desiredLiqPrice,
                            map(to),
                            map(validator),
                            currentPriceData,
                            previousActionsData,
                            ethAmount
                        );
                    } else if (command == Commands.INITIATE_CLOSE) {
                        // TODO INITIATE_CLOSE
                    } else if (command == Commands.VALIDATE_DEPOSIT) {
                        (
                            address validator,
                            bytes memory depositPriceData,
                            PreviousActionsData memory previousActionsData,
                            uint256 ethAmount
                        ) = abi.decode(inputs, (address, bytes, PreviousActionsData, uint256));
                        _usdnValidateDeposit(map(validator), depositPriceData, previousActionsData, ethAmount);
                    } else if (command == Commands.VALIDATE_WITHDRAWAL) {
                        (
                            address validator,
                            bytes memory withdrawalPriceData,
                            PreviousActionsData memory previousActionsData,
                            uint256 ethAmount
                        ) = abi.decode(inputs, (address, bytes, PreviousActionsData, uint256));
                        _usdnValidateWithdrawal(map(validator), withdrawalPriceData, previousActionsData, ethAmount);
                    } else if (command == Commands.VALIDATE_OPEN) {
                        (
                            address validator,
                            bytes memory depositPriceData,
                            PreviousActionsData memory previousActionsData,
                            uint256 ethAmount
                        ) = abi.decode(inputs, (address, bytes, PreviousActionsData, uint256));
                        _usdnValidateOpenPosition(map(validator), depositPriceData, previousActionsData, ethAmount);
                    } else if (command == Commands.VALIDATE_CLOSE) {
                        // TODO VALIDATE_CLOSE
                    } else if (command == Commands.LIQUIDATE) {
                        // TODO LIQUIDATE
                    } else if (command == Commands.VALIDATE_PENDING) {
                        // TODO VALIDATE_PENDING
                    } else {
                        revert InvalidCommandType(command);
                    }
                }
            } else {
                if (command == Commands.WRAP_USDN) {
                    // TODO WRAP_USDN
                } else if (command == Commands.UNWRAP_WUSDN) {
                    // TODO UNWRAP_WUSDN
                } else if (command == Commands.WRAP_STETH) {
                    // equivalent: abi.decode(inputs, address)
                    address recipient;
                    assembly {
                        recipient := calldataload(inputs.offset)
                    }
                    success_ = LidoRouter._wrapSTETH(map(recipient));
                } else if (command == Commands.UNWRAP_WSTETH) {
                    // equivalent: abi.decode(inputs, address)
                    address recipient;
                    assembly {
                        recipient := calldataload(inputs.offset)
                    }
                    success_ = LidoRouter._unwrapSTETH(map(recipient));
                } else {
                    revert InvalidCommandType(command);
                }
            }
        } else {
            if (command == Commands.SMARDEX_SWAP_EXACT_IN) {
                // TODO SMARDEX_SWAP_EXACT_IN
            } else if (command == Commands.SMARDEX_SWAP_EXACT_OUT) {
                // TODO SMARDEX_SWAP_EXACT_OUT
            } else {
                revert InvalidCommandType(command);
            }
        }
    }
}
