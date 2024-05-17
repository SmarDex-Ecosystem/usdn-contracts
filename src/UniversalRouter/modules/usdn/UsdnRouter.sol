// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { UsdnImmutables } from "src/UniversalRouter/modules/usdn/UsdnImmutables.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";
import { IWusdn } from "src/interfaces/IWusdn.sol";

/// @title Router for Usdn
abstract contract UsdnRouter is UsdnImmutables, Permit2Payments {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWusdn;

    function _wrapUSDN(uint256 value, address receiver) internal {
        IERC20 usdn = IERC20(USDN);
        uint256 balance = usdn.balanceOf(address(this));

        if (value == Constants.CONTRACT_BALANCE) {
            value = balance;
        } else if (value > balance) {
            revert InsufficientToken();
        }

        if (value > 0) {
            uint256 allowance = usdn.allowance(address(this), WUSDN);
            if (allowance < value) {
                usdn.safeIncreaseAllowance(WUSDN, value - allowance);
                IWusdn(WUSDN).deposit(value, receiver);
            }
        }
    }

    function _unwrapUSDN(uint256 value, address receiver, address owner) internal {
        IWusdn wusdn = IWusdn(WUSDN);
        uint256 balance = wusdn.balanceOf(address(this));

        if (value == Constants.CONTRACT_BALANCE) {
            value = balance;
        } else if (value > balance) {
            revert InsufficientToken();
        }

        if (value > 0) {
            wusdn.redeem(value, receiver, owner);
        }
    }
}
