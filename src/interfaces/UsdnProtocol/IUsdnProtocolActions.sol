// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

interface IUsdnProtocolActions is IUsdnProtocolTypes {
    /**
     * @notice Initiate an open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateOpenPosition` action
     * The price validation might require payment according to the return value of the {validationCost} function
     * of the middleware
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data
     * The transaction must have `_securityDepositValue` in value
     * In case liquidations are pending, this function will not initiate the position (`isInitiated_` would be false)
     * If the estimated effect of this action would lead to a protocol imbalance exceeding
     * `s._openExpoImbalanceLimitBps`, the transaction will revert. Note that due to the validation price not being
     * known and other factors like liquidations, it's possible that the imbalance slightly exceeds this value at times
     * @param amount The amount of assets to deposit
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty. Note: the position's
     * leverage is the result of a calculation involving the liquidation price without the penalty. As such, if the
     * penalty is changed before this position is recorded, the position's leverage might not match the user's
     * expectations.
     * @param userMaxPrice The maximum price at which the position can be opened (with _priceFeedDecimals). Note that
     * there is no guarantee that the effective price during validation will be below this value. The userMinPrice is
     * compared with the price after confidence interval, penalty, etc... However, if the
     * temporary entry price is below this threshold, the initiate action will revert
     * @param userMaxLeverage The maximum leverage for the newly created position
     * @param to The address that will be the owner of the position
     * @param validator The address that will validate the open position
     * Be aware that if the validator is not an EOA, it must be a contract that implements a receive function to accept
     * the returned Ether
     * @param deadline The deadline of the open position to be initiated
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return isInitiated_ Whether the position was initiated. If false, the security deposit was refunded
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
    ) external payable returns (bool isInitiated_, PositionId memory posId_);

    /**
     * @notice Validate a pending open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateOpenPosition` action
     * The price validation might require payment according to the return value of the {validationCost} function
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
     * In case liquidations are pending (`outcome_ == LongActionOutcome.PendingLiquidations`),
     * the pending action will not be removed from the queue, and the user will have to try again
     * In case the position was liquidated by this call (`outcome_ == LongActionOutcome.Liquidated`),
     * this function will refund the security deposit and remove the pending action from the queue
     * Note that this action could imbalance the protocol past the set limits, which is expected and unavoidable
     * @param validator The address that has the pending open position action to validate
     * @param openPriceData The price data corresponding to the sender's pending open position action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return outcome_ The effect that the call had on the pending action (processed, liquidated, pending liquidations)
     * @return posId_ The position ID, which might have changed due to the new entry price moving the position to a new
     * liquidation tick. If the position was liquidated, then `NO_POSITION_TICK` is returned for the `tick` field
     */
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (LongActionOutcome outcome_, PositionId memory posId_);

    /**
     * @notice Initiate a close position action
     * @dev Currently, the `msg.sender` must match the position's user address
     * Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action
     * The price validation might require payment according to the return value of the {validationCost} function
     * of the middleware
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and the transaction will revert
     * The appropriate amount and total expo are taken out of the tick and put in a pending state during this operation
     * Thus, calculations don't consider those anymore. The exit price (and thus profit) is not yet set definitively,
     * and will be done during the `validate` action
     * The transaction must have `_securityDepositValue` in value
     * In case liquidations are pending (`outcome_ == LongActionOutcome.PendingLiquidations`),
     * the pending action will not be removed from the queue, and the user will have to try again
     * In case the position was liquidated by this call (`outcome_ == LongActionOutcome.Liquidated`),
     * this function will refund the security deposit and remove the pending action from the queue
     * If the estimated effect of this action would lead to a protocol imbalance exceeding
     * `s._closeExpoImbalanceLimitBps`, the transaction will revert. Note that due to the validation price not being
     * known and other factors like liquidations, it's possible that the imbalance slightly exceeds this value at times
     * @param posId The unique identifier of the position to close
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param userMinPrice The minimum price at which the position can be closed (with _priceFeedDecimals). Note that
     * there is no guarantee that the effective price during validation will be below this value. The userMinPrice is
     * compared with the price after confidence interval, penalty, etc... However, if the
     * temporary entry price is below this threshold, the initiate action will revert
     * @param to The address that will receive the assets
     * @param validator The address that will validate the close action
     * Be aware that if the validator is not an EOA, it must be a contract that implements a receive function to accept
     * the returned Ether
     * @param deadline The deadline of the close position to be initiated
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @param delegationSignature An optional EIP712 signature to provide when closing a position on the owner's behalf
     * If used, it needs to be encoded with `abi.encodePacked(r, s, v)`
     * @return outcome_ The effect that the call had on the pending action
     * (processed, liquidated, pending liquidations)
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
    ) external payable returns (LongActionOutcome outcome_);

    /**
     * @notice Validate a pending close position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateClosePosition` action
     * The price validation might require payment according to the return value of the {validationCost} function
     * of the middleware
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the `initiate` action
     * This operation calculates the final exit price and profit of the long position and performs the payout
     * Note: this function always sends the security deposit of the validator's pending action to the validator, even
     * if the validation deadline has passed
     * Users wanting to validate an actionable pending action must use another function such as
     * `validateActionablePendingActions` to earn the corresponding security deposit
     * In case liquidations are pending (`outcome_ == LongActionOutcome.PendingLiquidations`),
     * the pending action will not be removed from the queue, and the user will have to try again
     * In case the position was liquidated by this call (`outcome_ == LongActionOutcome.Liquidated`),
     * this function will refund the security deposit and remove the pending action from the queue
     * Note that this action could imbalance the protocol past the set limits, which is expected and unavoidable
     * @param validator The validator of the close pending action, not necessarily the position owner
     * @param closePriceData The price data corresponding to the sender's pending close position action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return outcome_ The effect that the call had on the pending action
     * (processed, liquidated, pending liquidations)
     */
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (LongActionOutcome outcome_);

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateDeposit` action
     * The price validation might require payment according to the return value of the {validationCost} function
     * of the middleware
     * The transaction must have `_securityDepositValue` in value
     * In case liquidations are pending, this function might not initiate the deposit (and `success_` would be false)
     * If the estimated effect of this action would lead to a protocol imbalance exceeding
     * `s._depositExpoImbalanceLimitBps`, the transaction will revert. Note that due to the validation price not being
     * known and other factors like liquidations, it's possible that the imbalance slightly exceeds this value at times
     * @param amount The amount of assets to deposit
     * @param sharesOutMin The minimum amount of USDN shares to receive. Note that there is no guarantee that the
     * effective minted amount at validation will exceed this value. Price changes during the interval could negatively
     * affect the minted amount. However, if the predicted amount is below this threshold, the initiate action will
     * revert
     * @param to The address that will receive the USDN tokens
     * @param validator The address that will validate the deposit
     * Be aware that if the validator is not an EOA, it must be a contract that implements a receive function to accept
     * the returned Ether
     * @param deadline The deadline of the deposit to be initiated
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the deposit was initiated
     */
    function initiateDeposit(
        uint128 amount,
        uint256 sharesOutMin,
        address to,
        address payable validator,
        uint256 deadline,
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
     * Note that this action could imbalance the protocol past the set limits, which is expected and unavoidable
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
     * The price validation might require payment according to the return value of the {validationCost} function
     * of the middleware
     * The transaction must have `_securityDepositValue` in value
     * If the estimated effect of this action would lead to a protocol imbalance exceeding
     * `s._withdrawalExpoImbalanceLimitBps`, the transaction will revert. Note that due to the validation price not
     * being known and other factors like liquidations, it's possible that the imbalance slightly exceeds this value at
     * times
     * @param usdnShares The amount of USDN shares to burn (Max 5708990770823839524233143877797980545530986495 which is
     * equivalent to 5.7B USDN token before any rebase. The token amount limit increases with each rebase)
     * In case liquidations are pending, this function might not initiate the withdrawal (and `success_` would be false)
     * @param amountOutMin The estimated minimum amount of assets to receive. Note that there is no guarantee that the
     * effective withdrawal amount at validation will exceed this value. Price changes during the interval could
     * negatively affect the withdrawal amount. However, if the predicted amount is below this threshold, the initiate
     * action will revert
     * @param to The address that will receive the assets
     * @param validator The address that will validate the withdrawal
     * Be aware that if the validator is not an EOA, it must be a contract that implements a receive function to accept
     * the returned Ether
     * @param deadline The deadline of the withdrawal to be initiated
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the withdrawal was initiated
     */
    function initiateWithdrawal(
        uint152 usdnShares,
        uint256 amountOutMin,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Validate a pending withdrawal action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateWithdrawal` action
     * The price validation might require payment according to the return value of the {validationCost} function
     * of the middleware The timestamp corresponding to the price data is calculated by adding the mandatory
     * `validationDelay` (from the oracle middleware) to the timestamp of the `initiate` action Note: this function
     * always sends the security deposit of the validator's pending action to the validator, even
     * if the validation deadline has passed Users wanting to validate an actionable pending action must use another
     * function such as `validateActionablePendingActions` to earn the corresponding security deposit
     * In case liquidations are pending, this function might not validate the withdrawal (and `success_` would be false)
     * Note that this action could imbalance the protocol past the set limits, which is expected and unavoidable
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
     * @notice Liquidate positions according to the current asset price
     * limited to a maximum of `MAX_LIQUIDATION_ITERATION` ticks
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.Liquidation` action
     * The price validation might require payment according to the return value of the {validationCost} function
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
     * @dev The price validation might require payment according to the return value of the {validationCost}
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
     * @param delegationSignature An optional EIP712 signature to provide when position ownership is transferred on the
     * owner's behalf. If used, it needs to be encoded with `abi.encodePacked(r, s, v)`
     */
    function transferPositionOwnership(PositionId calldata posId, address newOwner, bytes calldata delegationSignature)
        external;

    /**
     * @notice Get the domain separator v4
     * @return The domain separator v4
     */
    function domainSeparatorV4() external view returns (bytes32);
}
