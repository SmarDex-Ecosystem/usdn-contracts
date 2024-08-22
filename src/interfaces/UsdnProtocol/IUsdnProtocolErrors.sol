// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUsdnProtocolErrors
 * @notice Errors for the USDN Protocol
 */
interface IUsdnProtocolErrors {
    /// @dev Indicates that not enough ether was provided to cover the cost of price validation
    error UsdnProtocolInsufficientOracleFee();

    /// @dev Indicates that the sender could not accept the ether refund
    error UsdnProtocolEtherRefundFailed();

    /// @dev Indicates that the provided amount is zero
    error UsdnProtocolZeroAmount();

    /// @dev Indicates that the provided `to` address is invalid
    error UsdnProtocolInvalidAddressTo();

    /// @dev Indicates that the provided `validator` address is invalid
    error UsdnProtocolInvalidAddressValidator();

    /**
     * @dev Indicates that the initialization deposit is too low
     * @param minInitAmount The minimum initialization amount
     */
    error UsdnProtocolMinInitAmount(uint256 minInitAmount);

    /**
     * @dev Indicates that the provided USDN contract has a total supply above zero at deployment
     * @param usdnAddress The USDN contract address
     */
    error UsdnProtocolInvalidUsdn(address usdnAddress);

    /**
     * @dev Indicates that the provided asset decimals are invalid
     * @param assetDecimals The wanted asset decimals
     */
    error UsdnProtocolInvalidAssetDecimals(uint8 assetDecimals);

    /// @dev Indicates that the token decimals are not equal to `TOKENS_DECIMALS`
    error UsdnProtocolInvalidTokenDecimals();

    /// @dev Indicates that the user is not allowed to perform an action
    error UsdnProtocolUnauthorized();

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

    /// @dev Indicates that the long position is too small
    error UsdnProtocolLongPositionTooSmall();

    /**
     * @dev Indicates that the liquidation price is higher than or equal to the start price
     * @param liquidationPrice The wanted liquidation price
     * @param startPrice The start price
     */
    error UsdnProtocolInvalidLiquidationPrice(uint128 liquidationPrice, uint128 startPrice);

    /**
     * @dev Indicates that the liquidation price exceeds the safety margin
     * @param liquidationPrice The wanted liquidation price
     * @param maxLiquidationPrice The maximum liquidation price
     */
    error UsdnProtocolLiquidationPriceSafetyMargin(uint128 liquidationPrice, uint128 maxLiquidationPrice);

    /**
     * @dev Indicates that the provided tick version is outdated (transactions have been liquidated)
     * @param currentVersion The current tick version
     * @param providedVersion The provided tick version
     */
    error UsdnProtocolOutdatedTick(uint256 currentVersion, uint256 providedVersion);

    /// @dev Indicates that the position cannot be closed because it's not validated yet
    error UsdnProtocolPositionNotValidated();

    /// @dev Indicates that the provided position fee exceeds the maximum allowed
    error UsdnProtocolInvalidPositionFee();

    /// @dev Indicates that the provided vault fee exceeds the maximum allowed
    error UsdnProtocolInvalidVaultFee();

    /// @dev Indicates that the provided rebalancer bonus exceeds the maximum allowed
    error UsdnProtocolInvalidRebalancerBonus();

    /// @dev Indicates that the provided ratio exceeds the maximum allowed
    error UsdnProtocolInvalidBurnSdexOnDepositRatio();

    /// @dev Indicates that the new middleware address value is invalid
    error UsdnProtocolInvalidMiddlewareAddress();

    /// @dev Indicate that the new `minLeverage` value is invalid
    error UsdnProtocolInvalidMinLeverage();

    /// @dev Indicates that the new `maxLeverage` value is invalid
    error UsdnProtocolInvalidMaxLeverage();

    /// @dev Indicates that the new validation deadline value is invalid
    error UsdnProtocolInvalidValidationDeadline();

    /// @dev Indicates that the new `liquidationPenalty` value is invalid
    error UsdnProtocolInvalidLiquidationPenalty();

    /// @dev Indicates that the new `safetyMargin` value is invalid
    error UsdnProtocolInvalidSafetyMarginBps();

    /// @dev Indicates that the new `liquidationIteration` value is invalid
    error UsdnProtocolInvalidLiquidationIteration();

    /// @dev Indicates that the new `EMAPeriod` value is invalid
    error UsdnProtocolInvalidEMAPeriod();

    /// @dev Indicates that the new `fundingSF` value is invalid
    error UsdnProtocolInvalidFundingSF();

    /// @dev Indicates that the provided address for the `LiquidationRewardsManager` contract address is invalid
    error UsdnProtocolInvalidLiquidationRewardsManagerAddress();

    /// @dev Indicates that the provided fee basis point value is invalid
    error UsdnProtocolInvalidProtocolFeeBps();

    /// @dev Indicates that the provided fee collector address is invalid
    error UsdnProtocolInvalidFeeCollector();

    /// @dev Indicates that the provided security deposit is lower than `_securityDepositValue`
    error UsdnProtocolSecurityDepositTooLow();

    /// @dev Indicates that the ether balance of the contract at the end of the action is not the expected one
    error UsdnProtocolUnexpectedBalance();

    /// @dev Indicates that the trading expo imbalance limit provided is invalid
    error UsdnProtocolInvalidExpoImbalanceLimit();

    /// @dev The imbalance target on the long side is invalid
    error UsdnProtocolInvalidLongImbalanceTarget();

    /**
     * @dev Indicates that the protocol imbalance limit is reached
     * @param imbalanceBps The imbalance in basis points
     */
    error UsdnProtocolImbalanceLimitReached(int256 imbalanceBps);

    /// @dev Indicates that the tick of the rebalancer position is invalid
    error UsdnProtocolInvalidRebalancerTick();

    /// @dev Indicates that the protocol vault expo is invalid
    error UsdnProtocolInvalidVaultExpo();

    /// @dev Indicates that the protocol long expo is invalid
    error UsdnProtocolInvalidLongExpo();

    /// @dev Indicates that the provided total expo is zero
    error UsdnProtocolZeroTotalExpo();

    /**
     * @dev Indicates that the data provided to validate an actionable pending action is invalid (zero length or length
     * mismatch)
     */
    error UsdnProtocolInvalidPendingActionData();

    /// @dev Indicates that the provided target USDN price is invalid
    error UsdnProtocolInvalidTargetUsdnPrice();

    /// @dev Indicates that the provided USDN rebase threshold is invalid
    error UsdnProtocolInvalidUsdnRebaseThreshold();

    /**
     * @dev Indicates that the amount to close in a position is higher than the amount in the position itself
     * @param amountToClose The wanted amount to close
     * @param positionAmount The amount in the position
     */
    error UsdnProtocolAmountToCloseHigherThanPositionAmount(uint128 amountToClose, uint128 positionAmount);

    /// @dev Indicates that the deposit amount is too small, leading to no USDN minted or no SDEX burned
    error UsdnProtocolDepositTooSmall();

    /// @dev Indicates that the long trading expo is zero, we can't get the effective tick for a liquidation price
    error UsdnProtocolZeroLongTradingExpo();
}
