// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolActions
 * @notice Interface for the USDN Protocol Actions.
 */
interface IUsdnProtocolActions is IUsdnProtocolTypes {
    /**
     * @notice Initiates an open position action.
     * @dev Consult the current oracle middleware for price data format.
     * Requires `_securityDepositValue` to be included in the transaction value. In case of pending liquidations, this
     * function will not initiate the position (`isInitiated_` would be false). Reverts if the protocol imbalance
     * exceeds `_openExpoImbalanceLimitBps`.
     * @param amount The amount of assets to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the penalty.
     * @param userMaxPrice The user's wanted maximum price at which the position can be opened, not guaranteed.
     * @param userMaxLeverage The user's wanted maximum leverage for the new position.
     * @param to The address that will owns of the position.
     * @param validator The address that validates the open position. If the validator is not an EOA, it must be a
     * contract that implements a receive function to accept the returned Ether.
     * @param deadline The deadline for initiating the open position.
     * @param currentPriceData The price data used for temporary leverage and entry price computations.
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @return isInitiated_ Whether the position was successfully initiated. If false, the security deposit was refunded
     * @return posId_ The unique position identifier. If the position was not initiated, the ID is
     * `NO_POSITION_TICK`.
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
     * @notice Validates a pending open position action.
     * @dev Consult the current oracle middleware for price data format.
     * It is possible for this operation to change the tick, tick version and index of the position, in which case we  emit
     * the `LiquidationPriceUpdated` event.
     * This function always sends the security deposit to the validator. So users wanting to earn the corresponding
     * security deposit must use `validateActionablePendingActions`.
     * In case liquidations are pending (`outcome_ == LongActionOutcome.PendingLiquidations`), the pending action will
     * not be removed from the queue, and the user will have to try again.
     * In case the position was liquidated by this call (`outcome_ == LongActionOutcome.Liquidated`), this function will
     * refund the security deposit and remove the pending action from the queue.
     * @param validator The address associated with the pending open position.
     * @param openPriceData The price data for the pending open position.
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @return outcome_ The effect on the pending action (processed, liquidated, or pending liquidations).
     * @return posId_ The position ID after validation (or `NO_POSITION_TICK` if liquidated).
     */
    function validateOpenPosition(
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (LongActionOutcome outcome_, PositionId memory posId_);

    /**
     * @notice Initiates a close position action.
     * @dev Consult the current oracle middleware for price data format.
     * Requires `_securityDepositValue` to be included in the transaction value.
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and the transaction will revert.
     * In case liquidations are pending (`outcome_ == LongActionOutcome.PendingLiquidations`), the pending action will
     * not be removed from the queue, and the user will have to try again.
     * In case the position was liquidated by this call (`outcome_ == LongActionOutcome.Liquidated`), this function will
     * refund the security deposit and remove the pending action from the queue.
     * Reverts if the imbalance exceeds `_closeExpoImbalanceLimitBps`.
     * @param posId The unique identifier of the position to close.
     * @param amountToClose The amount of collateral to remove.
     * @param userMinPrice The user's wanted minimum price for closing the position, not guaranteed.
     * @param to The address that will receive the assets.
     * @param validator The address validating the close action.If the validator is not an EOA, it must be a contract
     * that implements a receive function to accept the returned Ether.
     * @param deadline The deadline for initiating the close position.
     * @param currentPriceData The price data for temporary calculations.
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @param delegationSignature Optional EIP712 signature for delegated action.
     * @return outcome_ The effect on the pending action (processed, liquidated, or pending liquidations).
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
     * @notice Validates a pending close position action.
     * @dev Consult the current oracle middleware for price data format.
     * This function calculates the final exit price, determines the profit of the long position, and performs the
     * payout.
     * This function always sends the security deposit to the validator. So users wanting to earn the corresponding
     * security deposit must use `validateActionablePendingActions`.
     * In case liquidations are pending (`outcome_ == LongActionOutcome.PendingLiquidations`),
     * the pending action will not be removed from the queue, and the user will have to try again.
     * In case the position was liquidated by this call (`outcome_ == LongActionOutcome.Liquidated`),
     * this function will refund the security deposit and remove the pending action from the queue.
     * @param validator The address of the validator for the close pending action.
     * @param closePriceData The price data for the pending close position action.
     * @param previousActionsData The data required to validate actionable pending actions.
     * @return outcome_ The outcome of the action (processed, liquidated, or pending liquidations).
     */
    function validateClosePosition(
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (LongActionOutcome outcome_);

    /**
     * @notice Initiates a deposit of assets into the vault to mint USDN.
     * @dev Consult the current oracle middleware for price data format.
     * Requires `_securityDepositValue` to be included in the transaction value.
     * In case liquidations are pending, this function might not initiate the deposit, and `success_` would be false.
     * If the estimated effect of this action would lead to a protocol imbalance exceeding
     * `depositExpoImbalanceLimitBps`, the transaction will revert.
     * @param amount The amount of assets to deposit.
     * @param sharesOutMin The minimum amount of USDN shares to receive, not guaranteed.
     * @param to The address that will receive the USDN tokens.
     * @param validator The address that will validate the deposit. If the validator is not an EOA, it must be a
     * contract that implements a receive function to accept the returned Ether.
     * @param deadline The deadline for initiating the deposit.
     * @param currentPriceData The current price data.
     * @param previousActionsData The data required to validate actionable pending actions.
     * @return success_ Indicates whether the deposit was successfully initiated.
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
     * @notice Validates a pending deposit action.
     * @dev Consult the current oracle middleware for price data format.
     *  This function always sends the security deposit to the validator. So users wanting to earn the corresponding
     * security deposit must use `validateActionablePendingActions`.
     * If liquidations are pending, the validation may fail, and `success_` would be false.
     * @param validator The address associated with the pending deposit action. If the validator is not an EOA, it must
     * be a contract that implements a receive function to accept the returned Ether.
     * @param depositPriceData The price data for the pending deposit action.
     * @param previousActionsData The data required to validate actionable pending actions.
     * @return success_ Indicates whether the deposit was successfully validated.
     */
    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Initiates a withdrawal of assets from the vault using USDN tokens.
     * @dev Consult the current oracle middleware for price data format.
     * Requires `_securityDepositValue` to be included in the transaction value.
     * If the estimated effect of this action would lead to a protocol imbalance exceeding
     * `withdrawalExpoImbalanceLimitBps`, the transaction will revert.
     * Note that in case liquidations are pending, this function might not initiate the withdrawal, and `success_` would
     * be false.
     * @param usdnShares The amount of USDN shares to burn.
     * @param amountOutMin The estimated minimum amount of assets to receive.
     * @param to The address that will receive the assets.
     * @param validator The address that will validate the withdrawal. If the validator is not an EOA, it must
     * be a contract that implements a receive function to accept the returned Ether.
     * @param deadline The deadline for initiating the the withdrawal.
     * @param currentPriceData The current price data.
     * @param previousActionsData The data required to validate actionable pending actions.
     * @return success_ Indicates whether the withdrawal was successfully initiated.
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
     * @notice Validates a pending withdrawal action.
     * @dev Consult the current oracle middleware for price data format.
     * This function always sends the security deposit to the validator. So users wanting to earn the corresponding
     * security deposit must use `validateActionablePendingActions`.
     * In case liquidations are pending, this function might not validate the withdrawal, and `success_` would be false.
     * @param validator The address associated with the pending withdrawal action.  If the validator is not an EOA, it
     * must be a contract that implements a receive function to accept the returned Ether.
     * @param withdrawalPriceData The price data for the pending withdrawal action.
     * @param previousActionsData The data required to validate actionable pending actions.
     * @return success_ Indicates whether the withdrawal was successfully validated.
     */
    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

    /**
     * @notice Liquidates positions based on the provided asset price.
     * @dev Consult the current oracle middleware for price data format.
     * Each tick is liquidated in constant time. The tick version is incremented for each liquidated tick.
     * @param currentPriceData The price data, les than `OracleMiddleware._pythRecentPriceDelay` old.
     * @return liquidatedTicks_ Information about the liquidated ticks.
     */
    function liquidate(bytes calldata currentPriceData)
        external
        payable
        returns (LiqTickInfo[] memory liquidatedTicks_);

    /**
     * @notice Manually validates actionable pending actions.
     * @dev Consult the current oracle middleware for price data format.
     * The timestamp for each pending action is calculated by adding the `OracleMiddleware.validationDelay` to its
     * initiation timestamp.
     * @param previousActionsData The data required to validate actionable pending actions.
     * @param maxValidations The maximum number of actionable pending actions to validate.At least one validation will
     * be performed.
     * @return validatedActions_ The number of successfully validated actions.
     */
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        returns (uint256 validatedActions_);

    /**
     * @notice Transfers the ownership of a position to another address.
     * @dev This function reverts if the caller is not the position owner, if the position does not exist, or if the new
     * owner's address is the zero address.
     * If the new owner is a contract that implements the `IOwnershipCallback` interface, its `ownershipCallback`
     * function will be invoked after the transfer.
     * @param posId The unique identifier of the position.
     * @param newOwner The address of the new position owner.
     * @param delegationSignature An optional EIP712 signature to authorize the transfer on the owner's behalf.
     */
    function transferPositionOwnership(PositionId calldata posId, address newOwner, bytes calldata delegationSignature)
        external;

    /**
     * @notice Retrieves the domain separator used in EIP-712 signatures.
     * @return domainSeparatorV4_ The domain separator compliant with EIP-712.
     */
    function domainSeparatorV4() external view returns (bytes32 domainSeparatorV4_);
}
