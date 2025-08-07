// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { Wusdn } from "../Usdn/Wusdn.sol";

/// @title ERC-4626 Wrapper for WUSDN
contract WusdnVault is ERC4626 {
    Wusdn constant WUSDN = Wusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);

    constructor() ERC4626(WUSDN) ERC20("WusdnVault", "WusdnV") { }
}
