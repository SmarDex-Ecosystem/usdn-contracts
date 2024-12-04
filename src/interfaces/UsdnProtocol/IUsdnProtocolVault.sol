// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUsdnProtocolVault
 * @notice Interface for the vault layer of the USDN protocol.
 */
interface IUsdnProtocolVault {
    /**
     * @notice Calculates the predicted USDN token price based on the given asset price and timestamp.
     * @dev The effects of the funding and the PnL of the long positions since the last contract state update are taken
     * into account.
     * @param currentPrice The current or predicted asset price.
     * @param timestamp The timestamp corresponding to `currentPrice`.
     * @return price_ The predicted USDN token price.
     */
    function usdnPrice(uint128 currentPrice, uint128 timestamp) external view returns (uint256 price_);

    /**
     * @notice Calculates the USDN token price based on the given asset price at the current timestamp.
     * @dev The effects of the funding and the PnL of the long positions since the last contract state update are taken
     * into account.
     * @param currentPrice The asset price at `block.timestamp`.
     * @return price_ The calculated USDN token price.
     */
    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_);

    /**
     * @notice Gets the amount of assets in the vault for the given asset price and timestamp.
     * @dev The effects of the funding, the PnL of the long positions and the accumulated fees since the last contract
     * state update are taken into account, but not liquidations. If the provided timestamp is older than the last
     * state update, the function reverts with `UsdnProtocolTimestampTooOld`.
     * @param currentPrice The current or predicted asset price.
     * @param timestamp The timestamp corresponding to `currentPrice` (must not be earlier than `_lastUpdateTimestamp`).
     * @return available_ The available vault balance (cannot be less than 0).
     */
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (uint256 available_);
}
