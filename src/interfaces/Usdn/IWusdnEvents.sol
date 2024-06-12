// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Events for the WUSDN token contract
 * @notice Contains all custom events emitted by the WUSDN token contract (omitting events from OpenZeppelin)
 */
interface IWusdnEvents {
    /**
     * @notice Emitted when a user wraps USDN to mint WUSDN
     * @param from The address of the user that wrapped the USDN
     * @param to The address of the user that received the WUSDN
     * @param usdnAmount The amount of USDN wrapped
     * @param wusdnAmount The amount of WUSDN minted
     */
    event Wrap(address indexed from, address indexed to, uint256 usdnAmount, uint256 wusdnAmount);

    /**
     * @notice Emitted when a user unwraps WUSDN to redeem USDN
     * @param from The address of the user that withdrew the WUSDN
     * @param to The address of the user that received the USDN
     * @param wusdnAmount The amount of WUSDN unwrapped
     * @param usdnAmount The amount of USDN redeemed
     */
    event Unwrap(address indexed from, address indexed to, uint256 wusdnAmount, uint256 usdnAmount);
}
