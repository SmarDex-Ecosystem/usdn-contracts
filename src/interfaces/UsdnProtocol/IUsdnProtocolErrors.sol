// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IUsdnProtocolErrors
 * @notice Errors for the USDN Protocol
 */
interface IUsdnProtocolErrors {
    /// @notice Not enough ether was provided to cover the cost of price validation
    error UsdnProtocolInsufficientOracleFee();

    /// @dev Indicates that the sender could not accept the ether refund
    error UsdnProtocolEtherRefundFailed();

    /// @dev Indicates that the provided amount is zero
    error UsdnProtocolZeroAmount();

    /// @dev Indicates that the initialization deposit is too low
    error UsdnProtocolMinInitAmount(uint256 minInitAmount);

    /// @dev Indicates that the provided USDN contract has a total supply above zero at deployment
    error UsdnProtocolInvalidUsdn(address usdnAddress);

    /// @dev Indicates that the asset decimals are invalid
    error UsdnProtocolInvalidAssetDecimals(uint8 assetDecimals);

    /// @dev Indicates that the user is not allowed to perform an action
    error UsdnProtocolUnauthorized();

    /// @dev Indicates that the token transfer didn't yield the expected balance change
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

    /// @dev Indicates that the provided position fee exceeds the maximum allowed
    error UsdnProtocolMaxPositionFeeExceeded();

    /// @dev Indicates that the provided address for the LiquidationRewardsManager contract is the 0 address
    error UsdnProtocolLiquidationRewardsManagerIsZeroAddress();

    /// @dev Indicates that the new middleware address value is invalid.
    error UsdnProtocolInvalidMiddlewareAddress();

    /// @dev Indicate that the new minLeverage value is invalid.
    error UsdnProtocolInvalidMinLeverage();

    /// @dev Indicates that the new maxLeverage value is invalid.
    error UsdnProtocolInvalidMaxLeverage();

    /// @dev Indicates that the new validation deadline value is invalid.
    error UsdnProtocolInvalidValidationDeadline();

    /// @dev Indicates that the new liquidationPenalty value is invalid.
    error UsdnProtocolInvalidLiquidationPenalty();

    /// @dev Indicates that the new safetyMargin value is invalid.
    error UsdnProtocolInvalidSafetyMarginBps();

    /// @dev Indicates that the new liquidationIteration value is invalid.
    error UsdnProtocolInvalidLiquidationIteration();

    /// @dev Indicates that the new EMAPeriod value is invalid.
    error UsdnProtocolInvalidEMAPeriod();

    /// @dev Indicates that the new fundingSF value is invalid.
    error UsdnProtocolInvalidFundingSF();

    /// @dev Indicates that the provided address for the LiquidationRewardsManager contract address is invalid.
    error UsdnProtocolInvalidLiquidationRewardsManagerAddress();

    /// @dev Indicates that the provided fee percentage value is invalid.
    error UsdnProtocolInvalidProtocolFeeBps();

    /// @dev Indicates that the provided fee collector address is invalid
    error UsdnProtocolInvalidFeeCollector();
}
