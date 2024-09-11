// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IWstETH } from "./IWstETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IStETH is IERC20, IERC20Permit {
    error setStEthPerTokenTooSmall(uint256 currentStEthPerToken, uint256 newStEthPerToken);

    function setStEthPerToken(uint256 _stEthAmount, IWstETH wstETH) external returns (uint256);

    function mint(address account, uint256 amount) external;

    function deposit(address account) external payable;

    function sweep(address to) external;
}
