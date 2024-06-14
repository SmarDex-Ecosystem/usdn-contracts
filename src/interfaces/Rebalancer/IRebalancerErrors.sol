// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IRebalancerErrors {
    /// @dev Indicates that the user assets are used in a position
    error RebalancerUserNotPending();

    /// @dev IndicatesIndicates that the user assets are not used in a position
    error RebalancerUserPending();

    /// @dev Indicates that the `to` address is invalid
    error RebalancerInvalidAddressTo();

    /// @dev Indicates that the `validator` address is invalid
    error RebalancerInvalidAddressValidator();

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

    /// @dev Indicates that the caller is not authorized to perform the action
    error RebalancerUnauthorized();
}
