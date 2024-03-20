// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title SmardexToken (SDEX), ERC-20 token
 */
contract Sdex is ERC20Permit {
    constructor() ERC20("Smardex", "SDEX") ERC20Permit("Smardex") { }

    /**
     * @notice Mint tokens to the caller
     * @param _supply How many tokens should be minted
     */
    function mint(uint256 _supply) external {
        _mint(msg.sender, _supply);
    }
}
