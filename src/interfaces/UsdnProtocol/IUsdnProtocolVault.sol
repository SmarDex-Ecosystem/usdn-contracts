// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUsdnProtocolVault
 * @notice Interface for the vault layer of the USDN protocol
 */
interface IUsdnProtocolVault {
    /**
     * @notice Get the predicted value of the USDN token price for the given asset price and timestamp
     * @dev The effect of the funding and any profit or loss of the long positions since the last contract state
     * update is taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The predicted value of the USDN token price
     */
    function usdnPrice(uint128 currentPrice, uint128 timestamp) external view returns (uint256);

    /**
     * @notice Get the value of the USDN token price for the given asset price and the current timestamp
     * @dev The effect of the funding and any profit or loss of the long positions since the last contract state
     * update is taken into account
     * @param currentPrice The most recent/current asset price
     * @return The value of the USDN token price
     */
    function usdnPrice(uint128 currentPrice) external view returns (uint256);

    /**
     * @notice Get the predicted value of the vault balance for the given asset price and timestamp
     * @dev The effects of the funding and any profit or loss of the long positions since the last contract state
     * update is taken into account, as well as the fees. If the provided timestamp is older than the last state
     * update, the function reverts with `UsdnProtocolTimestampTooOld`. The value cannot be below 0
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The vault balance
     */
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (uint256);
}
