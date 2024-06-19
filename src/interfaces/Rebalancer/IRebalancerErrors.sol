// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IRebalancerErrors {
    /// @dev Indicates that the user assets are used in a position
    error RebalancerUserInPosition();

    /// @dev Indicates that the user assets are not used in a position
    error RebalancerUserPending();

    /// @dev Indicates that the user assets are used in a position
    error RebalancerUserNotPending();

    /// @dev Indicates that the `to` address is invalid
    error RebalancerInvalidAddressTo();

    /// @dev Indicates that the amount of assets is invalid
    error RebalancerInvalidAmount();

    /// @dev Indicates that the amount to deposit is insufficient
    error RebalancerInsufficientAmount();

    /// @dev Indicates that the amount to withdraw is greater than the amount deposited
    error RebalancerWithdrawAmountTooLarge();

    /// @dev Indicates that the provided max leverage is invalid
    error RebalancerInvalidMaxLeverage();

    /// @dev Indicates that the wanted minimum asset deposit is invalid
    error RebalancerInvalidMinAssetDeposit();

    /// @dev Indicates that the provided time limits are invalid
    error RebalancerInvalidTimeLimits();

    /// @dev Indicates that the caller is not authorized to perform the action
    error RebalancerUnauthorized();

    /// @dev Indicates that the address could not accept the ether refund
    error RebalancerEtherRefundFailed();

    /// @dev Indicates that the user still needs to validate their deposit or withdrawal
    error RebalancerActionNotValidated();

    /// @dev Indicates that the user already has a position that is pending inclusion into the protocol
    error RebalancerUserAlreadyPending();

    /// @dev Indicates that the user has no deposit or withdrawal that is pending validation
    error RebalancerActionWasValidated();

    /// @dev Indicates that the validation happened too early, user must wait `_timeLimits.validationDelay`
    error RebalancerValidateTooEarly();

    /// @dev Indicates that the validation happened too late, user must wait `_timeLimits.actionCooldown`
    error RebalancerActionCooldown();
}
