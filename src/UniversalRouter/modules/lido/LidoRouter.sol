// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";

import { LidoImmutables } from "src/UniversalRouter/modules/lido/LidoImmutables.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";

/// @title Router for StEth
abstract contract LidoRouter is LidoImmutables, Permit2Payments {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IWstETH;

    /**
     * @notice Wrap all of the contract's stETH into wstETH
     * @param recipient The recipient of the wstETH
     * @return Whether the wrapping was successful
     */
    function _wrapSTETH(address recipient) internal returns (bool) {
        uint256 amount = STETH.balanceOf(address(this));
        if (amount == 0) {
            return false;
        }
        STETH.forceApprove(address(WSTETH), amount);
        amount = WSTETH.wrap(amount);

        if (recipient != address(this)) {
            WSTETH.safeTransfer(recipient, amount);
        }
        return true;
    }

    /**
     * @notice Unwraps all of the contract's wstETH into stETH
     * @param recipient The recipient of the stETH
     * @return Whether the unwrapping was successful
     */
    function _unwrapSTETH(address recipient) internal returns (bool) {
        uint256 amount = WSTETH.balanceOf(address(this));
        if (amount == 0) {
            return false;
        }
        amount = WSTETH.unwrap(amount);

        if (recipient != address(this)) {
            STETH.safeTransfer(recipient, amount);
        }

        return true;
    }
}
