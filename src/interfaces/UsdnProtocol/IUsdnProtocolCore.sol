// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolCore
 * @notice Interface for the core layer of the USDN protocol
 */
interface IUsdnProtocolCore is IUsdnProtocolTypes {
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
     * @notice Get the predicted value of the vault trading exposure for the given asset price and timestamp
     * @dev The effects of the funding and any profit or loss of the long positions since the last contract state
     * update is taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The vault trading exposure
     */
    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Retrieve a list of pending actions, one of which must be validated by the next user action in the
     * protocol
     * @dev If this function returns a non-empty list of pending actions, then the next user action MUST include the
     * corresponding list of price update data and raw indices as the last parameter
     * @param currentUser The address of the user that will submit the price signatures for third-party actions
     * validations. This is used to filter out their actions from the returned list
     * @return actions_ The pending actions if any, otherwise an empty array. Note that some items can be zero-valued
     * and there is no need to provide price data for those (an empty `bytes` suffices)
     * @return rawIndices_ The raw indices of the actionable pending actions in the queue if any, otherwise an empty
     * array
     */
    function getActionablePendingActions(address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_);

    /**
     * @notice Retrieve a user pending action
     * @param user The user's address
     * @return action_ The pending action if any, otherwise a struct with all fields set to zero and
     * `ProtocolAction.None`
     */
    function getUserPendingAction(address user) external view returns (PendingAction memory action_);

    /**
     * @notice Initialize the protocol, making a first deposit and creating a first long position
     * @dev This function can only be called once, and no other user action can be performed until it is called
     * Consult the current oracle middleware implementation to know the expected format for the price data, using the
     * `ProtocolAction.Initialize` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of `IBaseOracleMiddleware`
     * @param depositAmount The amount of wstETH for the deposit
     * @param longAmount The amount of wstETH for the long
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
