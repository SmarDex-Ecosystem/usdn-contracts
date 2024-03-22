// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { IERC20 } from "src/interfaces/Usdn/IUsdn.sol";

/**
 * @title WUSDN token contract
 * @notice The USDN token is a delta neutral token that is inflating all users wallet. In order ton increase its value
 * value instead of getting inflated, the WUSDN token was created, a wrapped token of the USDN that is not
 * inflating, but increasing in value
 */
contract Wusdn is ERC4626, ERC20Permit {
    string internal constant NAME = "Wrapped Ultimate Synthetic Delta Neutral";
    string internal constant SYMBOL = "WUSDN";
    uint8 internal constant DECIMALS = 18;

    constructor(IERC20 asset) ERC20(NAME, SYMBOL) ERC4626(asset) ERC20Permit(NAME) { }

    function decimals() public pure override(ERC20, ERC4626) returns (uint8) {
        return DECIMALS;
    }
}
