// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IRebalancerErrors {
    /// @dev Indicates that the user assets are not used in a position
    error RebalancerUserPending();

    /// @dev Indicates that the user's assets were in a position version that is nor liquidated
    error RebalancerUserLiquidated();

    /// @dev Indicates that the `to` address is invalid
    error RebalancerInvalidAddressTo();

    /// @dev Indicates that the amount of assets is invalid
    error RebalancerInvalidAmount();

    /// @dev Indicates that the amount to deposit is insufficient
    error RebalancerInsufficientAmount();

    /// @dev Indicates that the provided max leverage is invalid
    error RebalancerInvalidMaxLeverage();

    /// @dev Indicates that the wanted minimum asset deposit is invalid
    error RebalancerInvalidMinAssetDeposit();

    /// @dev Indicates that the provided time limits are invalid
    error RebalancerInvalidTimeLimits();

    /// @dev Indicates that the caller is not authorized to perform the action
    error RebalancerUnauthorized();

    /// @dev Indicates that the user can't initiate or validate a deposit at the moment
    error RebalancerDepositUnauthorized();

    /// @dev Indicates that the user still needs to validate their deposit or withdrawal
    error RebalancerActionNotValidated();

    /// @dev Indicates that the user has no deposit or withdrawal that is pending validation
    error RebalancerNoPendingAction();

    /// @dev Indicates that the validation happened too early, user must wait `_timeLimits.validationDelay`
    error RebalancerValidateTooEarly();

    /// @dev Indicates that the validation happened too late, user must wait `_timeLimits.actionCooldown`
    error RebalancerActionCooldown();

    /// @dev Indicates that the user can't initiate or validate a withdrawal at the moment
    error RebalancerWithdrawalUnauthorized();

    /// @dev Indicates that the address could not accept the ether refund
    error RebalancerEtherRefundFailed();
}
