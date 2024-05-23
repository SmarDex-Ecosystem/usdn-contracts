// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";

import { LidoImmutables } from "src/UniversalRouter/modules/lido/LidoImmutables.sol";
import { IWSTETH } from "src/UniversalRouter/interfaces/IWSTETH.sol";

/// @title Router for StEth
abstract contract LidoRouter is LidoImmutables, Permit2Payments {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWSTETH;

    /**
     * @notice Wrap an amount of stETH into wstETH
     * @param recipient The recipient of the wstETH
     * @param amount The amount of wstETH desired
     */
    function _wrapSTETH(address recipient, uint256 amount) internal {
        IERC20 steth = IERC20(STETH);
        if (amount == Constants.CONTRACT_BALANCE) {
            amount = steth.balanceOf(address(this));
        } else if (amount > steth.balanceOf(address(this))) {
            revert InsufficientToken();
        }

        if (amount > 0) {
            uint256 allowance = steth.allowance(address(this), WSTETH);
            if (allowance < amount) {
                steth.safeIncreaseAllowance(WSTETH, amount - allowance);
            }

            IWSTETH wsteth = IWSTETH(WSTETH);
            amount = wsteth.wrap(amount);

            if (recipient != address(this)) {
                wsteth.safeTransfer(recipient, amount);
            }
        }
    }

    /**
     * @notice Unwraps all of the contract's wstETH into stETH
     * @param recipient The recipient of the stETH
     * @param amountMinimum The minimum amount of stETH desired
     */
    function _unwrapSTETH(address recipient, uint256 amountMinimum) internal {
        IWSTETH wsteth = IWSTETH(WSTETH);
        uint256 balanceWSTETH = wsteth.balanceOf(address(this));
        if (balanceWSTETH > 0) {
            uint256 amountSTETH = wsteth.unwrap(balanceWSTETH);

            if (amountSTETH < amountMinimum) {
                revert InsufficientToken();
            }

            if (recipient != address(this)) {
                IERC20(STETH).transfer(recipient, amountSTETH);
            }
        }
    }
}
