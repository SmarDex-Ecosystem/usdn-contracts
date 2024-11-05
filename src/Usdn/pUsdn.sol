// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract pUsdn is ERC20, ERC20Permit {
    constructor()
        ERC20("pre Ultimate Synthetic Delta Neutral", "pUSDN")
        ERC20Permit("pre Ultimate Synthetic Delta Neutral")
    {
        _mint(0xB0470cF15B22a6A32c49a7C20E3821B944A76058, 5_000_000 * 10 ** decimals());
        _mint(0x1E3e1128F6bC2264a19D7a065982696d356879c5, 9_995_000_000 * 10 ** decimals());
    }
}
