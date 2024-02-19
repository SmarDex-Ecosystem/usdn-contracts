// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract WstETH is ERC20, ERC20Permit {
    constructor() ERC20("Wrapped liquid staked Ether 2.0", "wstETH") ERC20Permit("Wrapped liquid staked Ether 2.0") {
        _mint(msg.sender, 4_000_000 * 10 ** decimals());
    }

    /// @dev Mint wstETH to the specified address
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Mint wstETH to the specified address and approve the spender
    function mintAndApprove(address to, uint256 amount, address spender, uint256 value) external {
        _mint(to, amount);
        _approve(to, spender, value);
    }

    /// @dev Returns the amount of ETH per stETH (mock value)
    function stEthPerToken() public pure returns (uint256) {
        return 1.15 ether;
    }

    /// @dev Receive ETH and mint wstETH
    receive() external payable {
        _mint(msg.sender, msg.value * 1 ether / stEthPerToken());
    }
}
