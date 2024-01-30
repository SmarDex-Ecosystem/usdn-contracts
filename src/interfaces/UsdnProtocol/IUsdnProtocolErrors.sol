// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/**
 * @title IUsdnProtocolErrors
 * @notice Errors for the USDN Protocol
 */
interface IUsdnProtocolErrors {
    /// @dev Indicates that the provided amount is zero
    error UsdnProtocolZeroAmount();

    /// @dev Indicates that the initilization deposit is too low
    error UsdnProtocolMinInitAmount(uint256 minInitAmount);

    /// @dev Indicates that the provided USDN contract has a total supply above zero at deployment
    error UsdnProtocolInvalidUsdn(address usdnAddress);

    /// @dev Indicates that the user is not allowed to perform an action
    error UsdnProtocolUnauthorized();

    /// @dev Indicates that the the token transfer didn't yield the expected balance change
    error UsdnProtocolIncompleteTransfer(address to, uint256 effectiveBalance, uint256 expectedBalance);

    /// @dev Indicates that the user already has a pending action
    error UsdnProtocolPendingAction();

    /// @dev Indicates that the user has no pending action
    error UsdnProtocolNoPendingAction();

    /// @dev Indicates that the user has a pending action but its action type is not the expected one
    error UsdnProtocolInvalidPendingAction();

    /// @dev Indicates that the provided timestamp is too old (pre-dates the last balances update)
    error UsdnProtocolTimestampTooOld();

    /// @dev Indicates that the provided collateral and liquidation price result in a leverage that is too low
    error UsdnProtocolLeverageTooLow();

    /// @dev Indicates that the provided collateral and liquidation price result in a leverage that is too high
    error UsdnProtocolLeverageTooHigh();

    /// @dev Indicates that the liquidation price is higher than or equal to the start price
    error UsdnProtocolInvalidLiquidationPrice(uint128 liquidationPrice, uint128 startPrice);

    /// @dev Indicates that the liquidation price exceeds the safety margin
    error UsdnProtocolLiquidationPriceSafetyMargin(uint128 liquidationPrice, uint128 maxLiquidationPrice);

    /// @dev Indicates that the provided tick version is outdated (transactions have been liquidated)
    error UsdnProtocolOutdatedTick(uint256 currentVersion, uint256 providedVersion);
}
