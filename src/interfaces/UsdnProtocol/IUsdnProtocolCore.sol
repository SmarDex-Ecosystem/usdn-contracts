// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUsdnProtocolCore
 * @notice Interface for the core layer of the USDN protocol
 */
interface IUsdnProtocolCore {
    /**
     * @notice Get the predicted value of the funding since the last state update for the given timestamp
     * @dev When multiplied with the long trading exposure, the funding value gives the asset balance that needs to be
     * paid to the vault side (or long side if negative)
     * If the provided timestamp is older than the last state update, the function reverts with
     * `UsdnProtocolTimestampTooOld`
     * @param timestamp The current timestamp
     * @return funding_ The magnitude of the funding (with `FUNDING_RATE_DECIMALS` decimals) since the last update
     * timestamp
     * @return fundingPerDay_ The value of the funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals
     * @return oldLongExpo_ The long trading exposure after the last state update
     */
    function funding(uint128 timestamp)
        external
        view
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_);

    /**
     * @notice Initialize the protocol, making a first deposit and creating a first long position
     * @dev This function can only be called once, and no other user action can be performed until it is called
     * Consult the current oracle middleware implementation to know the expected format for the price data, using the
     * `ProtocolAction.Initialize` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of `IBaseOracleMiddleware`
     * @param depositAmount The amount of assets for the deposit
     * @param longAmount The amount of assets for the long
     * @param desiredLiqPrice The desired liquidation price for the long, without penalty
     * @param currentPriceData The current price data
     */
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable;
}
