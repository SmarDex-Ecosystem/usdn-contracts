// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title SmardexToken (SDEX), ERC-20 token
 */
contract Sdex is ERC20Permit {
    uint8 private testDecimals;

    constructor() ERC20("Smardex", "SDEX") ERC20Permit("Smardex") {
        testDecimals = super.decimals();
    }

    /// @dev Mint SDEX to the specified address and approve the spender
    function mintAndApprove(address to, uint256 amount, address spender, uint256 value) external {
        _mint(to, amount);
        _approve(to, spender, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Test utils functions                            */
    /* -------------------------------------------------------------------------- */

    function setDecimals(uint8 newDecimals) external {
        testDecimals = newDecimals;
    }

    function decimals() public view override returns (uint8) {
        return testDecimals;
    }
}
