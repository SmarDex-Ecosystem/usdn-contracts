// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract WstETH is ERC20, ERC20Permit {
    constructor() ERC20("Wrapped liquid staked Ether 2.0", "wstETH") ERC20Permit("Wrapped liquid staked Ether 2.0") {
        _mint(msg.sender, 4_000_000 * 10 ** decimals());
    }

    /// @dev Mint wstETH to the specified address
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Returns the amount of stETH per wstETH (mock value)
    function stEthPerToken() public pure returns (uint256) {
        return 1.15 ether;
    }

    /// @dev Receive ETH and mint wstETH
    receive() external payable {
        _mint(address(this), msg.value * 1 ether / stEthPerToken());
    }
}
