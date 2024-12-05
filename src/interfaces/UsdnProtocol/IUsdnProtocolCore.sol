// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUsdnProtocolCore
 * @notice Interface for the core layer of the USDN protocol.
 */
interface IUsdnProtocolCore {
    /**
     * @notice Computes the predicted funding value since the last state update for the specified timestamp.
     * @dev The funding value, when multiplied by the long trading exposure, represents the asset balance to be
     * transferred to the vault side, or to the long side if the value is negative.
     * Reverts with `UsdnProtocolTimestampTooOld` if the given timestamp is older than the last state update.
     * @param timestamp The timestamp to use for the computation.
     * @return funding_ The funding magnitude (with `FUNDING_RATE_DECIMALS` decimals) since the last update timestamp.
     * @return fundingPerDay_ The funding rate per day (with `FUNDING_RATE_DECIMALS` decimals).
     * @return oldLongExpo_ The long trading exposure recorded at the last state update.
     */
    function funding(uint128 timestamp)
        external
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_);

    /**
     * @notice Initializes the protocol by making an initial deposit and creating the first long position.
     * @dev This function can only be called once. No other user actions can be performed until the protocol
     * is initialized.
     * @param depositAmount The amount of assets to deposit.
     * @param longAmount The amount of assets for the long position.
     * @param desiredLiqPrice The desired liquidation price for the long position, excluding the liquidation penalty.
     * @param currentPriceData The encoded current price data.
     */
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable;
}
