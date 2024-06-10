// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Events for the WUSDN token contract
 * @notice Contains all custom events emitted by the WUSDN token contract (omitting events from OpenZeppelin)
 */
interface IWusdnEvents {
    /**
     * @notice Emitted when a user deposits USDN to mint WUSDN
     * @param sender The address of the user that deposited the USDN
     * @param owner The address of the user that received the WUSDN
     * @param assets The amount of USDN tokens deposited
     * @param shares The number of WUSDN shares minted
     */
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when a user withdraws WUSDN to redeem USDN
     * @param sender The address of the user that withdrew the WUSDN
     * @param receiver The address of the user that received the USDN
     * @param owner The address of that owned the WUSDN
     * @param assets The amount of USDN tokens withdrawn
     * @param shares The number of WUSDN shares burned
     */
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
}
