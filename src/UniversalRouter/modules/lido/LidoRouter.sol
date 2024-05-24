// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";

import { LidoImmutables } from "src/UniversalRouter/modules/lido/LidoImmutables.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { IStETH } from "src/UniversalRouter/interfaces/IStETH.sol";

/// @title Router for StEth
abstract contract LidoRouter is LidoImmutables, Permit2Payments {
    using SafeERC20 for IStETH;
    using SafeERC20 for IWstETH;

    /**
     * @notice Wrap an amount of stETH into wstETH
     * @param recipient The recipient of the wstETH
     * @param amount The amount of wstETH desired
     */
    function _wrapSTETH(address recipient, uint256 amount) internal {
        if (amount == Constants.CONTRACT_BALANCE) {
            amount = STETH.balanceOf(address(this));
        } else if (amount > STETH.balanceOf(address(this))) {
            revert InsufficientToken();
        }

        if (amount > 0) {
            STETH.forceApprove(address(WSTETH), amount);

            amount = WSTETH.wrap(amount);

            if (recipient != address(this)) {
                WSTETH.safeTransfer(recipient, amount);
            }
        }
    }

    /**
     * @notice Unwraps all of the contract's wstETH into stETH
     * @param recipient The recipient of the stETH
     * @param amountMinimum The minimum amount of stETH desired
     */
    function _unwrapSTETH(address recipient, uint256 amountMinimum) internal {
        uint256 balanceWSTETH = WSTETH.balanceOf(address(this));
        if (balanceWSTETH > 0) {
            uint256 amountSTETH = WSTETH.unwrap(balanceWSTETH);

            if (amountSTETH < amountMinimum) {
                revert InsufficientToken();
            }

            if (recipient != address(this)) {
                STETH.safeTransfer(recipient, amountSTETH);
            }
        }
    }
}
