// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolVault
 * @notice Interface for the vault layer of the USDN protocol
 */
interface IUsdnProtocolVault is IUsdnProtocolTypes {
    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateDeposit` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The transaction must have `_securityDepositValue` in value
     * In case liquidations are pending, this function might not initiate the deposit (and `success_` would be false)
     * @param amount The amount of assets to deposit
     * @param to The address that will receive the USDN tokens
     * @param validator The address that will validate the deposit
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the deposit was initiated
     */
    function initiateDeposit(
        uint128 amount,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Validate a pending deposit action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateDeposit` action
     * The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the `initiate` action
     * Note: this function always sends the security deposit of the validator's pending action to the validator, even
     * if the validation deadline has passed
     * Users wanting to validate an actionable pending action must use another function such as
     * `validateActionablePendingActions` to earn the corresponding security deposit
     * In case liquidations are pending, this function might not validate the deposit (and `success_` would be false)
     * @param validator The address that has the pending deposit action to validate
     * @param depositPriceData The price data corresponding to the sender's pending deposit action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the deposit was validated
     */
    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The transaction must have `_securityDepositValue` in value
     * @param usdnShares The amount of USDN shares to burn (Max 5708990770823839524233143877797980545530986495 which is
     * equivalent to 5.7B USDN token before any rebase. The token amount limit increases with each rebase)
     * In case liquidations are pending, this function might not initiate the withdrawal (and `success_` would be false)
     * @param to The address that will receive the assets
     * @param validator The address that will validate the withdrawal
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the withdrawal was initiated
     */
    function initiateWithdrawal(
        uint152 usdnShares,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Validate a pending withdrawal action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateWithdrawal` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the `initiate` action
     * Note: this function always sends the security deposit of the validator's pending action to the validator, even
     * if the validation deadline has passed
     * Users wanting to validate an actionable pending action must use another function such as
     * `validateActionablePendingActions` to earn the corresponding security deposit
     * In case liquidations are pending, this function might not validate the withdrawal (and `success_` would be false)
     * @param validator The address that has the pending withdrawal action to validate
     * @param withdrawalPriceData The price data corresponding to the sender's pending withdrawal action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the withdrawal was validated
     */
    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

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
     * update, the function reverts with `UsdnProtocolTimestampTooOld`
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The vault balance
     */
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);
}
