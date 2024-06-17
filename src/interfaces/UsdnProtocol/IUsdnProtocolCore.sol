// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolStorage } from "./IUsdnProtocolStorage.sol";
import { PendingAction } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolCore
 * @notice Interface for the core layer of the USDN protocol
 */
interface IUsdnProtocolCore is IUsdnProtocolStorage {
    /**
     * @notice The address that holds the minimum supply of USDN and the first minimum long position
     * @return The address
     */
    function DEAD_ADDRESS() external pure returns (address);

    /**
     * @notice The maximum number of actionable pending action items returned by `getActionablePendingActions`
     * @return The maximum value
     */
    function MAX_ACTIONABLE_PENDING_ACTIONS() external pure returns (uint256);

    /* -------------------------- Public view functions ------------------------- */

    /**
     * @notice Get the predicted value of the long balance for the given asset price and timestamp
     * @dev The effects of the funding rates and any profit or loss of the long positions since the last contract state
     * update is taken into account, as well as the fees. If the provided `timestamp` is older than the last state
     * update, the function reverts with {UsdnProtocolTimestampTooOld}
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The long balance
     */
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Get the predicted value of the vault balance for the given asset price and timestamp
     * @dev The effects of the funding rates and any profit or loss of the long positions since the last contract state
     * update is taken into account, as well as the fees. If the provided timestamp is older than the last state
     * update, the function reverts with {UsdnProtocolTimestampTooOld}
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The vault balance
     */
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Get the predicted value of the long trading exposure for the given asset price and timestamp
     * @dev The effects of the funding rates and any profit or loss of the long positions since the last contract state
     * update is taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The long trading exposure
     */
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Calculation of the EMA of the funding rate
     * @param lastFunding The last funding rate
     * @param secondsElapsed The number of seconds elapsed since the last protocol action
     * @param emaPeriod The EMA period
     * @param previousEMA The previous EMA
     * @return The new EMA value
     */
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        external
        pure
        returns (int256);

    /* --------------------------  External functions --------------------------- */

    /**
     * @notice Get the predicted value of the funding since the last state update for the given timestamp
     * @dev When multiplied with the long trading exposure, this value gives the asset balance that needs to be paid to
     * the vault side (or long side if negative). If the provided timestamp is older than the last state update, the
     * function reverts with {UsdnProtocolTimestampTooOld}
     * @param timestamp The current timestamp
     * @return fund_ The magnitude of the funding (with `FUNDING_RATE_DECIMALS` decimals)
     * @return oldLongExpo_ The long trading exposure after the last state update
     */
    function funding(uint128 timestamp) external view returns (int256 fund_, int256 oldLongExpo_);

    /**
     * @notice Get the predicted value of the vault trading exposure for the given asset price and timestamp
     * @dev The effects of the funding rates and any profit or loss of the long positions since the last contract state
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
}
