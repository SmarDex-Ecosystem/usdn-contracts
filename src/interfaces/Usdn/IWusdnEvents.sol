// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Events for the WUSDN Token Contract
 * @notice Defines all custom events emitted by the WUSDN token contract.
 */
interface IWusdnEvents {
    /**
     * @notice The user wrapped USDN to mint WUSDN tokens.
     * @param from The address of the user who wrapped the USDN.
     * @param to The address of the recipient who received the WUSDN tokens.
     * @param usdnAmount The amount of USDN tokens wrapped.
     * @param wusdnAmount The amount of WUSDN tokens minted.
     */
    event Wrap(address indexed from, address indexed to, uint256 usdnAmount, uint256 wusdnAmount);

    /**
     * @notice The user unwrapped WUSDN tokens to redeem USDN.
     * @param from The address of the user who unwrapped the WUSDN tokens.
     * @param to The address of the recipient who received the USDN tokens.
     * @param wusdnAmount The amount of WUSDN tokens unwrapped.
     * @param usdnAmount The amount of USDN tokens redeemed.
     */
    event Unwrap(address indexed from, address indexed to, uint256 wusdnAmount, uint256 usdnAmount);
}
