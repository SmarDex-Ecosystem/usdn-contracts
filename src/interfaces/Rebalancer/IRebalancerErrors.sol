// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Rebalancer Errors
 * @notice Defines all custom errors thrown by the Rebalancer contract.
 */
interface IRebalancerErrors {
    /// @dev The user's assets are not used in a position.
    error RebalancerUserPending();

    /// @dev The user's assets were in a position that has been liquidated.
    error RebalancerUserLiquidated();

    /// @dev The `to` address is invalid.
    error RebalancerInvalidAddressTo();

    /// @dev The amount of assets is invalid.
    error RebalancerInvalidAmount();

    /// @dev The amount to deposit is insufficient.
    error RebalancerInsufficientAmount();

    /// @dev The given maximum leverage is invalid.
    error RebalancerInvalidMaxLeverage();

    /// @dev The given minimum asset deposit is invalid.
    error RebalancerInvalidMinAssetDeposit();

    /// @dev The given time limits are invalid.
    error RebalancerInvalidTimeLimits();

    /// @dev The caller is not authorized to perform the action.
    error RebalancerUnauthorized();

    /// @dev The user can't initiate or validate a deposit at this time.
    error RebalancerDepositUnauthorized();

    /// @dev The user must validate their deposit or withdrawal.
    error RebalancerActionNotValidated();

    /// @dev The user has no pending deposit or withdrawal requiring validation.
    error RebalancerNoPendingAction();

    /// @dev Ton was attempted too early, the user must wait for `_timeLimits.validationDelay`.
    error RebalancerValidateTooEarly();

    /// @dev Ton was attempted too late, the user must wait for `_timeLimits.actionCooldown`.
    error RebalancerActionCooldown();

    /// @dev The user can't initiate or validate a withdrawal at this time.
    error RebalancerWithdrawalUnauthorized();

    /// @dev The address was unable to accept the Ether refund.
    error RebalancerEtherRefundFailed();

    /// @dev The signature provided for delegation is invalid.
    error RebalancerInvalidDelegationSignature();

    /**
     * @dev The user can't initiate a close position until the given timestamp has passed.
     * @param closeLockedUntil The timestamp until which the user must wait to perform a close position action.
     */
    error RebalancerCloseLockedUntil(uint256 closeLockedUntil);
}
