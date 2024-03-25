// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/**
 * @title Interface containing event signatures from various external contracts
 */
interface IEvents {
    /* --------------------------------- IERC20 --------------------------------- */
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /* ------------------------------- ERC20Permit ------------------------------ */
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);
}
