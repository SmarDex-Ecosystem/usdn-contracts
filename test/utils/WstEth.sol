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

    /// @dev Returns the amount of ETH per stETH (mock value)
    function stEthPerToken() public pure returns (uint256) {
        return 1.15 ether;
    }

    /// @dev Returns the amount of wstETH per stETH (mock value)
    function getWstETHByStETH(uint256 _stETHAmount) external pure returns (uint256) {
        return _stETHAmount * 1.15 ether / 1 ether;
    }

    /// @dev Receive ETH and mint wstETH
    receive() external payable {
        _mint(msg.sender, msg.value * 1 ether / stEthPerToken());
    }
}
