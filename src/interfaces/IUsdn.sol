// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

interface IUsdn {
    function mint(address to, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}
