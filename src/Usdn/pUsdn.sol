// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract pUsdn is ERC20, ERC20Permit {
    /**
     * @notice Create an instance of the pUSDN token
     * @param hotWallet Address to create the liquidity pool
     * @param multisig Address of the multisig
     */
    constructor(address hotWallet, address multisig)
        ERC20("pre Ultimate Synthetic Delta Neutral", "pUSDN")
        ERC20Permit("pre Ultimate Synthetic Delta Neutral")
    {
        _mint(hotWallet, 5_000_000 * 10 ** decimals());
        _mint(multisig, 9_995_000_000 * 10 ** decimals());
    }
}
