// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title Rebalancer Errors
 * @notice Defines all custom errors emitted by the Rebalancer contract.
 */
interface IRebalancerErrors {
    /// @dev Indicates that the user's assets are not used in a position.
    error RebalancerUserPending();

    /// @dev Indicates that the user's assets are in a position that has not been liquidated.
    error RebalancerUserLiquidated();

    /// @dev Indicates that the `to` address is invalid.
    error RebalancerInvalidAddressTo();

    /// @dev Indicates that the amount of assets is invalid.
    error RebalancerInvalidAmount();

    /// @dev Indicates that the amount to deposit is insufficient.
    error RebalancerInsufficientAmount();

    /// @dev Indicates that the given maximum leverage is invalid.
    error RebalancerInvalidMaxLeverage();

    /// @dev Indicates that the given minimum asset deposit is invalid.
    error RebalancerInvalidMinAssetDeposit();

    /// @dev Indicates that the given time limits are invalid.
    error RebalancerInvalidTimeLimits();

    /// @dev Indicates that the caller is not authorized to perform the action.
    error RebalancerUnauthorized();

    /// @dev Indicates that the user can't initiate or validate a deposit at this time.
    error RebalancerDepositUnauthorized();

    /// @dev Indicates that the user must validate their deposit or withdrawal.
    error RebalancerActionNotValidated();

    /// @dev Indicates that the user has no pending deposit or withdrawal requiring validation.
    error RebalancerNoPendingAction();

    /// @dev Indicates that validation was attempted too early, the user must wait for `_timeLimits.validationDelay`.
    error RebalancerValidateTooEarly();

    /// @dev Indicates that validation was attempted too late, the user must wait for `_timeLimits.actionCooldown`.
    error RebalancerActionCooldown();

    /// @dev Indicates that the user can't initiate or validate a withdrawal at this time.
    error RebalancerWithdrawalUnauthorized();

    /// @dev Indicates that the address was unable to accept the Ether refund.
    error RebalancerEtherRefundFailed();

    /// @dev Indicates that the signature provided for delegation is invalid.
    error RebalancerInvalidDelegationSignature();

    /**
     * @dev Indicates that the user can't initiate a close position until the given timestamp has passed.
     * @param closeLockedUntil The timestamp until which the user must wait to perform a close position action.
     */
    error RebalancerCloseLockedUntil(uint256 closeLockedUntil);
}
