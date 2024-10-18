// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

interface IUsdnProtocolActions is IUsdnProtocolTypes {
    /**
     * @notice Initiate an open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateOpenPosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data
     * The transaction must have `_securityDepositValue` in value
     * In case liquidations are pending, this function might not initiate the position (and `success_` would be false)
     * @param amount The amount of assets to deposit
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty
     * @param userMaxPrice The maximum price at which the position can be opened (with _priceFeedDecimals). Note that
     * there is no guarantee that the effective price during validation will be below this value. The userMinPrice is
     * compared with the price after confidence interval, penalty, etc... However, if the
     * temporary entry price is below this threshold, the initiate action will revert
     * @param userMaxLeverage The maximum leverage for the newly created position
     * @param to The address that will be the owner of the position
     * @param validator The address that will validate the open position
     * @param deadline The deadline of the open position to be initiated
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the position was initiated
     * @return posId_ The unique position identifier. In case the position cannot be initiated, the tick number will
     * be `NO_POSITION_TICK`
     */
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        uint128 userMaxPrice,
        uint256 userMaxLeverage,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_, PositionId memory posId_);

    /**
     * @notice Validate a pending open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateOpenPosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the `initiate` action
     * This operation adjusts the entry price and initial leverage of the position
     * It is also possible for this operation to change the tick, `tickVersion` and index of the position, in which case
     * we emit the `LiquidationPriceUpdated` event
     * Note: this function always sends the security deposit of the validator's pending action to the validator, even
     * if the validation deadline has passed
     * Users wanting to validate an actionable pending action must use another function such as
     * `validateActionablePendingActions` to earn the corresponding security deposit
     * In case liquidations are pending or the position was liquidated, this function might not validate the position
     * (and `success_` would be false)
     * @param validator The address that has the pending open position action to validate
     * @param openPriceData The price data corresponding to the sender's pending open position action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the position was validated
     */
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Initiate a close position action
     * @dev Currently, the `msg.sender` must match the position's user address
     * Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and the transaction will revert
     * The appropriate amount and total expo are taken out of the tick and put in a pending state during this operation
     * Thus, calculations don't consider those anymore. The exit price (and thus profit) is not yet set definitively,
     * and will be done during the `validate` action
     * The transaction must have `_securityDepositValue` in value
     * In case liquidations are pending or the position was liquidated, this function might not initiate the closing
     * (and `success_` would be false)
     * @param posId The unique identifier of the position to close
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param userMinPrice The minimum price at which the position can be closed (with _priceFeedDecimals). Note that
     * there is no guarantee that the effective price during validation will be below this value. The userMinPrice is
     * compared with the price after confidence interval, penalty, etc... However, if the
     * temporary entry price is below this threshold, the initiate action will revert
     * @param to The address that will receive the assets
     * @param validator The address that will validate the close action
     * @param deadline The deadline of the close position to be initiated
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @param delegationSignature An optional eip712 signature to provide when closing a position on the owner's behalf
     * If used, it needs to be encoded with `abi.encodePacked(r, s, v)`
     * @return success_ Whether the closing was initiated
     */
    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        uint256 userMinPrice,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        bytes calldata delegationSignature
    ) external payable returns (bool success_);

    /**
     * @notice Validate a pending close position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateClosePosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the `initiate` action
     * This operation calculates the final exit price and profit of the long position and performs the payout
     * Note: this function always sends the security deposit of the validator's pending action to the validator, even
     * if the validation deadline has passed
     * Users wanting to validate an actionable pending action must use another function such as
     * `validateActionablePendingActions` to earn the corresponding security deposit
     * In case liquidations are pending or the position was liquidated, this function might not validate the closing
     * (and `success_` would be false)
     * @param validator The validator of the close pending action, not necessarily the position owner
     * @param closePriceData The price data corresponding to the sender's pending close position action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the closing was validated
     */
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Liquidate positions according to the current asset price
     * limited to a maximum of `MAX_LIQUIDATION_ITERATION` ticks
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.Liquidation` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * Each tick is liquidated in constant time. The tick version is incremented for each tick that was liquidated
     * @param currentPriceData The most recent price data
     * @return liquidatedTicks_ Information about the liquidated ticks
     */
    function liquidate(bytes calldata currentPriceData)
        external
        payable
        returns (LiqTickInfo[] memory liquidatedTicks_);

    /**
     * @notice Manually validate one or more actionable pending actions
     * @dev The price validation might require payment according to the return value of the `getValidationCost`
     * function of the middleware
     * The timestamp for the price data of each actionable pending action is calculated by adding the mandatory
     * `validationDelay` (from the oracle middleware) to the timestamp of the pending action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @param maxValidations The maximum number of actionable pending actions to validate. Even if zero, at least one
     * validation will be performed
     * @return validatedActions_ The number of validated actionable pending actions
     */
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        returns (uint256 validatedActions_);

    /**
     * @notice Transfer the ownership of a position to another address
     * @dev This function reverts if the msg.sender is not the position owner, if the position does not exist or if the
     * new owner's address is the zero address
     * If the new owner is a contract that supports the `IOwnershipCallback` interface, its `ownershipCallback` function
     * will be called after the transfer of ownership
     * @param posId The unique position ID
     * @param newOwner The new position owner
     */
    function transferPositionOwnership(PositionId calldata posId, address newOwner) external;

    /**
     * @notice Get the hash generated from the tick and a version
     * @param tick The tick number
     * @param version The tick version
     * @return The hash of the tick and version
     */
    function tickHash(int24 tick, uint256 version) external pure returns (bytes32);

    /**
     * @notice Get a long position identified by its tick, tickVersion and index
     * @param posId The unique position identifier
     * @return pos_ The position data
     * @return liquidationPenalty_ The liquidation penalty for that position (and associated tick)
     */
    function getLongPosition(PositionId calldata posId)
        external
        view
        returns (Position memory pos_, uint24 liquidationPenalty_);
}
