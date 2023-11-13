// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDN {
    event MultiplierAdjusted(uint256 old_multiplier, uint256 new_multiplier);

    error InvalidMultiplier(uint256 multiplier);

    error ERC2612ExpiredSignature(uint256 deadline);

    error ERC2612InvalidSigner(address signer, address owner);

    function totalShares() external view returns (uint256);

    function sharesOf(address account) external view returns (uint256);

    function mint(address to, uint256 amount) external;

    function adjustMultiplier(uint256 multiplier) external;

    function MINTER_ROLE() external view returns (bytes32);

    function ADJUSTMENT_ROLE() external view returns (bytes32);
}
