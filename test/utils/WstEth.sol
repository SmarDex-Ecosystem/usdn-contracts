// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract WstETH is ERC20, ERC20Permit {
    constructor() ERC20("Wrapped liquid staked Ether 2.0", "wstETH") ERC20Permit("Wrapped liquid staked Ether 2.0") {
        _mint(msg.sender, 4_000_000 * 10 ** decimals());
    }

    receive() external payable {
        _mint(address(this), msg.value);
    }
}
