// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUsdnProtocolErrors
 * @notice All errors used in the USDN Protocol.
 */
interface IUsdnProtocolErrors {
    /// @dev Insufficient Ether provided to cover the cost of price validation.
    error UsdnProtocolInsufficientOracleFee();

    /// @dev Ether refund to the sender failed.
    error UsdnProtocolEtherRefundFailed();

    /**
     * @dev Validator is not eligible for a security deposit refund.
     * @param validator The address of the validator.
     */
    error UsdnProtocolNotEligibleForRefund(address validator);

    /// @dev The provided amount is zero.
    error UsdnProtocolZeroAmount();

    /// @dev The provided `to` address is invalid.
    error UsdnProtocolInvalidAddressTo();

    /// @dev The provided `validator` address is invalid.
    error UsdnProtocolInvalidAddressValidator();

    /// @dev The initial amount provided during initialization is too small to support opening a long position.
    error UsdnProtocolMinInitAmount();

    /**
     * @dev The provided USDN token has a non-zero total supply at deployment.
     * @param usdnAddress The address of the USDN contract.
     */
    error UsdnProtocolInvalidUsdn(address usdnAddress);

    /**
     * @dev The asset's decimal precision is invalid.
     * @param assetDecimals The specified asset decimals.
     */
    error UsdnProtocolInvalidAssetDecimals(uint8 assetDecimals);

    /// @dev The token's decimals do not match `TOKENS_DECIMALS`.
    error UsdnProtocolInvalidTokenDecimals();

    /// @dev The caller is not authorized to perform the action.
    error UsdnProtocolUnauthorized();

    /// @dev A pending action already exists for the user.
    error UsdnProtocolPendingAction();

    /// @dev The user does not have any pending action.
    error UsdnProtocolNoPendingAction();

    /// @dev A pending action exists, but its type is not the expected one.
    error UsdnProtocolInvalidPendingAction();

    /// @dev The provided timestamp predates the last balance update.
    error UsdnProtocolTimestampTooOld();

    /// @dev The calculated leverage is below the minimum allowed.
    error UsdnProtocolLeverageTooLow();

    /// @dev The calculated leverage exceeds the maximum allowed.
    error UsdnProtocolLeverageTooHigh();

    /// @dev The amount of collateral in the long position is too small.
    error UsdnProtocolLongPositionTooSmall();

    /**
     * @dev The liquidation price exceeds or equals the starting price.
     * @param liquidationPrice The specified liquidation price.
     * @param startPrice The starting price.
     */
    error UsdnProtocolInvalidLiquidationPrice(uint128 liquidationPrice, uint128 startPrice);

    /**
     * @dev The liquidation price exceeds the safety margin.
     * @param liquidationPrice The specified liquidation price.
     * @param maxLiquidationPrice The maximum liquidation price.
     */
    error UsdnProtocolLiquidationPriceSafetyMargin(uint128 liquidationPrice, uint128 maxLiquidationPrice);

    /**
     * @dev The provided tick version is outdated due to liquidation.
     * @param currentVersion The current tick version.
     * @param providedVersion The provided tick version.
     */
    error UsdnProtocolOutdatedTick(uint256 currentVersion, uint256 providedVersion);

    /// @dev The position cannot be closed because it has not been validated yet.
    error UsdnProtocolPositionNotValidated();

    /// @dev The specified position fee exceeds the allowed maximum.
    error UsdnProtocolInvalidPositionFee();

    /// @dev The specified vault fee exceeds the allowed maximum.
    error UsdnProtocolInvalidVaultFee();

    /// @dev The specified SDEX rewards ratio exceeds the allowed maximum.
    error UsdnProtocolInvalidSdexRewardsRatio();

    /// @dev The specified rebalancer bonus exceeds the allowed maximum.
    error UsdnProtocolInvalidRebalancerBonus();

    /// @dev The specified ratio exceeds the allowed maximum.
    error UsdnProtocolInvalidBurnSdexOnDepositRatio();

    /// @dev The specified middleware address is invalid.
    error UsdnProtocolInvalidMiddlewareAddress();

    /// @dev The specified minimum leverage is invalid.
    error UsdnProtocolInvalidRebalancerMinLeverage();

    /// @dev The specified `minLeverage` value is invalid.
    error UsdnProtocolInvalidMinLeverage();

    /// @dev The specified `maxLeverage` value is invalid.
    error UsdnProtocolInvalidMaxLeverage();

    /// @dev The specified validation deadline is invalid.
    error UsdnProtocolInvalidValidatorDeadline();

    /// @dev The specified liquidation penalty is invalid.
    error UsdnProtocolInvalidLiquidationPenalty();

    /// @dev The specified safety margin basis points are invalid.
    error UsdnProtocolInvalidSafetyMarginBps();

    /// @dev The specified liquidation iteration value is invalid.
    error UsdnProtocolInvalidLiquidationIteration();

    /// @dev The specified EMA period is invalid.
    error UsdnProtocolInvalidEMAPeriod();

    /// @dev The specified funding scale factor (SF) is invalid.
    error UsdnProtocolInvalidFundingSF();

    /// @dev The specified `LiquidationRewardsManager` contract address is invalid.
    error UsdnProtocolInvalidLiquidationRewardsManagerAddress();

    /// @dev The specified protocol fee basis points are invalid.
    error UsdnProtocolInvalidProtocolFeeBps();

    /// @dev The specified fee collector address is invalid.
    error UsdnProtocolInvalidFeeCollector();

    /// @dev The specified security deposit is below the required value.
    error UsdnProtocolSecurityDepositTooLow();

    /// @dev The contract's ether balance after the action is not as expected.
    error UsdnProtocolUnexpectedBalance();

    /// @dev The specified trading exposure imbalance limit is invalid.
    error UsdnProtocolInvalidExpoImbalanceLimit();

    /// @dev The specified imbalance target is invalid.
    error UsdnProtocolInvalidLongImbalanceTarget();

    /**
     * @dev The protocol imbalance limit has been reached.
     * @param imbalanceBps The imbalance value in basis points.
     */
    error UsdnProtocolImbalanceLimitReached(int256 imbalanceBps);

    /// @dev The tick of the rebalancer position is invalid.
    error UsdnProtocolInvalidRebalancerTick();

    /// @dev The long total exposure value is invalid.
    error UsdnProtocolInvalidLongExpo();

    /// @dev The total exposure value is zero.
    error UsdnProtocolZeroTotalExpo();

    /// @dev Indicates that the data provided to validate an actionable pending action is invalid.
    error UsdnProtocolInvalidPendingActionData();

    /// @dev The specified target USDN price is invalid.
    error UsdnProtocolInvalidTargetUsdnPrice();

    /// @dev The specified USDN rebase threshold is invalid.
    error UsdnProtocolInvalidUsdnRebaseThreshold();

    /**
     * @dev The amount to close exceeds the position amount.
     * @param amountToClose The specified amount to close.
     * @param positionAmount The total amount in the position.
     */
    error UsdnProtocolAmountToCloseHigherThanPositionAmount(uint128 amountToClose, uint128 positionAmount);

    /// @dev The deposit amount is too small to mint USDN.
    error UsdnProtocolDepositTooSmall();

    /// @dev The long trading exposure is zero, making liquidation tick calculation impossible.
    error UsdnProtocolZeroLongTradingExpo();

    /// @dev The vault balance is zero, so the calculation cannot proceed.
    error UsdnProtocolEmptyVault();

    /// @dev The entry price exceeds the maximum specified by the user.
    error UsdnProtocolSlippageMaxPriceExceeded();

    /// @dev The current price is below the minimum specified by the user.
    error UsdnProtocolSlippageMinPriceExceeded();

    /// @dev The estimated amount of tokens to be received is less than expected.
    error UsdnProtocolAmountReceivedTooSmall();

    /// @dev The payment callback execution failed.
    error UsdnProtocolPaymentCallbackFailed();

    /// @dev The user initiate action's deadline has passed.
    error UsdnProtocolDeadlineExceeded();

    /// @dev The delegation signature is invalid.
    error UsdnProtocolInvalidDelegationSignature();

    /// @dev The specified security deposit value exceeds the allowed maximum
    error UsdnProtocolInvalidSecurityDeposit();

    /// @dev The specified minimum long position value exceeds the allowed maximum.
    error UsdnProtocolInvalidMinLongPosition();

    /// @dev The low latency delay of the specified oracle middleware contract is below the validator's deadline.
    error UsdnProtocolInvalidMiddlewareLowLatencyDelay();

    /**
     * @dev The minimum asset deposit of the specified rebalancer contract is below the protocol's minimum asset
     * deposit.
     */
    error UsdnProtocolInvalidRebalancerMinAssetDeposit();
}
