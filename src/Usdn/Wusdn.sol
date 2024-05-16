// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title WUSDN token contract
 * @notice The USDN token is a rebasing token that is inflating its users' balances periodically. To allow for
 * stable balances, the WUSDN token was created, a wrapped token of the USDN that is not inflating, but increasing in
 * value instead
 */
contract Wusdn is ERC4626, ERC20Permit {
    /// @notice Token name
    string internal constant NAME = "Wrapped Ultimate Synthetic Delta Neutral";

    /// @notice Token symbol
    string internal constant SYMBOL = "WUSDN";

    constructor(IERC20 asset) ERC20(NAME, SYMBOL) ERC4626(asset) ERC20Permit(NAME) { }

    /// @inheritdoc ERC20
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }
}
