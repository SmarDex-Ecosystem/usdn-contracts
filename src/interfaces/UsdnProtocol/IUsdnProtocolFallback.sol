// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

import { IBaseLiquidationRewardsManager } from "../LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../Usdn/IUsdn.sol";
import { IUsdnProtocolTypes } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolFallback
 * @notice Interface for the USDN protocol fallback functions
 */
interface IUsdnProtocolFallback is IUsdnProtocolTypes {
    /**
     * @notice Retrieves the list of pending actions that must be validated by the next user action in the protocol.
     * @dev If this function returns a non-empty list of pending actions, then the next user action MUST include the
     * corresponding list of price update data and raw indices as the last parameter. The user that processes those
     * pending actions will receive the corresponding security deposit.
     * @param currentUser The address of the user that will submit the price signatures for third-party actions
     * validations. This is used to filter out their actions from the returned list.
     * @param lookAhead Additionally to pending actions which are actionable at this moment `block.timestamp`, the
     * function will also return pending actions which will be actionable `lookAhead` seconds later. It is recommended
     * to use a non-zero value in order to account for the interval where the validation transaction will be pending. A
     * value of 30 seconds should already account for most situations and avoid reverts in case an action becomes
     * actionable after a user submits their transaction.
     * @param maxIter The maximum number of iterations when looking through the queue to find actionable pending
     * actions. This value will be clamped to [MIN_ACTIONABLE_PENDING_ACTIONS_ITER,_pendingActionsQueue.length()].
     * @return actions_ The pending actions if any, otherwise an empty array.
     * @return rawIndices_ The raw indices of the actionable pending actions in the queue if any, otherwise an empty
     * array. Each entry corresponds to the action in the `actions_` array, at the same index.
     */
    function getActionablePendingActions(address currentUser, uint256 lookAhead, uint256 maxIter)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_);

    /**
     * @notice Retrieves the pending action with `user` as the given validator.
     * @param user The user's address.
     * @return action_ The pending action if any, otherwise a struct with all fields set to zero and
     * `ProtocolAction.None`.
     */
    function getUserPendingAction(address user) external view returns (PendingAction memory action_);

    /**
     * @notice Computes the hash generated from the given tick number and version.
     * @param tick The tick number.
     * @param version The tick version.
     * @return hash_ The hash of the given tick number and version.
     */
    function tickHash(int24 tick, uint256 version) external pure returns (bytes32 hash_);

    /**
     * @notice Computes the liquidation price of the given tick number, taking into account the effects of funding.
     * @dev Uses the values from storage for the various variables. Note that ticks that are
     * not a multiple of the tick spacing cannot contain a long position.
     * @param tick The tick number.
     * @return price_ The liquidation price.
     */
    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_);

    /**
     * @notice Computes the liquidation price of the given tick number, taking into account the effects of funding.
     * @dev Uses the given values instead of the ones from the storage. Note that ticks that are not a multiple of the
     * tick spacing cannot contain a long position.
     * @param tick The tick number.
     * @param assetPrice The current/projected price of the asset.
     * @param longTradingExpo The trading exposure of the long side (total expo - balance long).
     * @param accumulator The liquidation multiplier accumulator.
     * @return price_ The liquidation price.
     */
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external view returns (uint128 price_);

    /**
     * @notice Computes an estimate of the amount of assets received when withdrawing.
     * @dev The result is a rough estimate and does not take into account rebases and liquidations.
     * @param usdnShares The amount of USDN shares to use in the withdrawal.
     * @param price The current/projected price of the asset.
     * @param timestamp The The timestamp corresponding to `price`.
     * @return assetExpected_ The expected amount of assets to be received.
     */
    function previewWithdraw(uint256 usdnShares, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_);

    /**
     * @notice Computes an estimate of USDN tokens to be minted and SDEX tokens to be burned when depositing.
     * @dev The result is a rough estimate and does not take into account rebases and liquidations.
     * @param amount The amount of assets to deposit.
     * @param price The current/projected price of the asset.
     * @param timestamp The timestamp corresponding to `price`.
     * @return usdnSharesExpected_ The amount of USDN shares to be minted.
     * @return sdexToBurn_ The amount of SDEX tokens to be burned.
     */
    function previewDeposit(uint256 amount, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_);

    /**
     * @notice Refunds the security deposit to the given validator if it has a liquidated initiated long position.
     * @dev The security deposit is always sent to the validator even if the pending action is actionable.
     * @param validator The address of the validator (must be payable as it will receive some native currency).
     */
    function refundSecurityDeposit(address payable validator) external;

    /// @notice Sends the accumulated SDEX token fees to the dead address. This function can be called by anyone.
    function burnSdex() external;

    /* -------------------------------------------------------------------------- */
    /*                               Admin functions                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Removes a stuck pending action and performs the minimal amount of cleanup necessary.
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly.
     * It will not refund any fees or burned SDEX.
     * @param validator The address of the validator of the stuck pending action.
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn). Must be payable.
     */
    function removeBlockedPendingAction(address validator, address payable to) external;

    /**
     * @notice Removes a stuck pending action with no cleanup.
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly.
     * Always try to use `removeBlockedPendingAction` first, and only call this function if the other one fails.
     * It will not refund any fees or burned SDEX.
     * @param validator The address of the validator of the stuck pending action.
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn). Must be payable.
     */
    function removeBlockedPendingActionNoCleanup(address validator, address payable to) external;

    /**
     * @notice Removes a stuck pending action and performs the minimal amount of cleanup necessary.
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly.
     * It will not refund any fees or burned SDEX.
     * @param rawIndex The raw index of the stuck pending action.
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn). Must be payable.
     */
    function removeBlockedPendingAction(uint128 rawIndex, address payable to) external;

    /**
     * @notice Removes a stuck pending action with no cleanup.
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly.
     * Always try to use `removeBlockedPendingAction` first, and only call this function if the other one fails.
     * It will not refund any fees or burned SDEX.
     * @param rawIndex The raw index of the stuck pending action.
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn). Must be payable.
     */
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to) external;

    /* -------------------------------------------------------------------------- */
    /*                             Immutables getters                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The number of ticks between usable ticks. Only tick numbers that are a multiple of the tick spacing can
     * be used for storing long positions.
     * @dev A tick spacing of 1 is equivalent to a 0.01% increase in price between ticks. A tick spacing of 100 is.
     * equivalent to a ~1.005% increase in price between ticks.
     * @return tickSpacing_ The tick spacing.
     */
    function getTickSpacing() external view returns (int24 tickSpacing_);

    /**
     * @notice Gets the address of the protocol's underlying asset (ERC20 token).
     * @return asset_ The address of the asset token.
     */
    function getAsset() external view returns (IERC20Metadata asset_);

    /**
     * @notice Gets the address of the SDEX ERC20 token.
     * @return sdex_ The address of the SDEX token.
     */
    function getSdex() external view returns (IERC20Metadata sdex_);

    /**
     * @notice Gets the number of decimals of the asset's price feed.
     * @return decimals_ The number of decimals of the asset's price feed.
     */
    function getPriceFeedDecimals() external view returns (uint8 decimals_);

    /**
     * @notice Gets the number of decimals of the underlying asset token.
     * @return decimals_ The number of decimals of the asset token.
     */
    function getAssetDecimals() external view returns (uint8 decimals_);

    /**
     * @notice Gets the address of the USDN ERC20 token.
     * @return usdn_ The address of USDN ERC20 token.
     */
    function getUsdn() external view returns (IUsdn usdn_);

    /**
     * @notice Gets the `MIN_DIVISOR` constant of the USDN token.
     * @dev Check the USDN contract for more information.
     * @return minDivisor_ The `MIN_DIVISOR` constant of the USDN token.
     */
    function getUsdnMinDivisor() external view returns (uint256 minDivisor_);

    /* -------------------------------------------------------------------------- */
    /*                             Parameters getters                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the oracle middleware contract.
     * @return oracleMiddleware_ The address of the oracle middleware contract.
     */
    function getOracleMiddleware() external view returns (IBaseOracleMiddleware oracleMiddleware_);

    /**
     * @notice Gets the liquidation rewards manager contract.
     * @return liquidationRewardsManager_ The address of the liquidation rewards manager contract.
     */
    function getLiquidationRewardsManager()
        external
        view
        returns (IBaseLiquidationRewardsManager liquidationRewardsManager_);

    /**
     * @notice Gets the rebalancer contract.
     * @return rebalancer_ The address of the rebalancer contract.
     */
    function getRebalancer() external view returns (IBaseRebalancer rebalancer_);

    /**
     * @notice Gets the lowest leverage that can be used to open a long position.
     * @return minLeverage_ The minimum leverage (with `LEVERAGE_DECIMALS` decimals).
     */
    function getMinLeverage() external view returns (uint256 minLeverage_);

    /**
     * @notice Gets the highest leverage that can be used to open a long position.
     * @dev A position can have a leverage a bit higher than this value under specific conditions involving
     * a change to the liquidation penalty setting.
     * @return maxLeverage_ The maximum leverage value (with `LEVERAGE_DECIMALS` decimals).
     */
    function getMaxLeverage() external view returns (uint256 maxLeverage_);

    /**
     * @notice Gets the deadline of the exclusivity period for the validator of a pending action with a low-latency
     * oracle.
     * @dev After this deadline, any user can validate the action with the low-latency oracle until the
     * OracleMiddleware's `_lowLatencyDelay`, and retrieve the security deposit for the pending action.
     * @return deadline_ The low-latency validation deadline of a validator (in seconds).
     */
    function getLowLatencyValidatorDeadline() external view returns (uint128 deadline_);

    /**
     * @notice Gets the deadline of the exclusivity period for the validator to confirm their action with the on-chain
     * oracle.
     * @dev After this deadline, any user can validate the pending action with the on-chain oracle and retrieve its
     * security deposit.
     * @return deadline_ The on-chain validation deadline of a validator (in seconds)
     */
    function getOnChainValidatorDeadline() external view returns (uint128 deadline_);

    /**
     * @notice Gets the liquidation penalty applied to the liquidation price when opening a position.
     * @return liquidationPenalty_ The liquidation penalty (in ticks).
     */
    function getLiquidationPenalty() external view returns (uint24 liquidationPenalty_);

    /**
     * @notice Gets the safety margin for the liquidation price of newly open positions.
     * @return safetyMarginBps_ The safety margin (in basis points).
     */
    function getSafetyMarginBps() external view returns (uint256 safetyMarginBps_);

    /**
     * @notice Gets the number of tick liquidations to perform when attempting to
     * liquidate positions during user actions.
     * @return iterations_ The number of iterations for liquidations during user actions.
     */
    function getLiquidationIteration() external view returns (uint16 iterations_);

    /**
     * @notice Gets the time frame for the EMA calculations.
     * @dev The EMA is set to the last funding rate when the time elapsed between 2 actions is greater than this value.
     * @return period_ The time frame of the EMA (in seconds).
     */
    function getEMAPeriod() external view returns (uint128 period_);

    /**
     * @notice Gets the scaling factor (SF) of the funding rate.
     * @return scalingFactor_ The scaling factor (with `FUNDING_SF_DECIMALS` decimals).
     */
    function getFundingSF() external view returns (uint256 scalingFactor_);

    /**
     * @notice Gets the fee taken by the protocol during the application of funding.
     * @return feeBps_ The fee applied to the funding (in basis points).
     */
    function getProtocolFeeBps() external view returns (uint16 feeBps_);

    /**
     * @notice Gets the fee applied when a long position is opened or closed.
     * @return feeBps_ The fee applied to a long position (in basis points).
     */
    function getPositionFeeBps() external view returns (uint16 feeBps_);

    /**
     * @notice Gets the fee applied during a vault deposit or withdrawal.
     * @return feeBps_ The fee applied to a vault action (in basis points).
     */
    function getVaultFeeBps() external view returns (uint16 feeBps_);

    /**
     * @notice Gets the rewards ratio given to the caller when burning SDEX tokens.
     * @return rewardsBps_ The rewards ratio (in basis points).
     */
    function getSdexRewardsRatioBps() external view returns (uint16 rewardsBps_);

    /**
     * @notice Gets the part of the remaining collateral given as a bonus to the Rebalancer upon liquidation of a tick.
     * @return bonusBps_ The fraction of the remaining collateral for the Rebalancer bonus (in basis points).
     */
    function getRebalancerBonusBps() external view returns (uint16 bonusBps_);

    /**
     * @notice Gets the ratio of SDEX tokens to burn per minted USDN.
     * @return ratio_ The ratio (to be divided by SDEX_BURN_ON_DEPOSIT_DIVISOR).
     */
    function getSdexBurnOnDepositRatio() external view returns (uint32 ratio_);

    /**
     * @notice Gets the amount of native tokens used as security deposit when opening a new position.
     * @return securityDeposit_ The amount of assets to use as a security deposit (in ether).
     */
    function getSecurityDepositValue() external view returns (uint64 securityDeposit_);

    /**
     * @notice Gets the threshold to reach to send accumulated fees to the fee collector.
     * @return threshold_ The amount of accumulated fees to reach (in `_assetDecimals`).
     */
    function getFeeThreshold() external view returns (uint256 threshold_);

    /**
     * @notice Gets the address of the fee collector.
     * @return feeCollector_ The address of the fee collector.
     */
    function getFeeCollector() external view returns (address feeCollector_);

    /**
     * @notice Returns the amount of time to wait before an action can be validated.
     * @dev This is also the amount of time to add to the initiate action timestamp to fetch the correct price data to
     * validate said action with a low-latency oracle.
     * @return delay_ The validation delay (in seconds).
     */
    function getMiddlewareValidationDelay() external view returns (uint256 delay_);

    /**
     * @notice Gets the expo imbalance limit when depositing assets (in basis points).
     * @return depositExpoImbalanceLimitBps_ The deposit expo imbalance limit.
     */
    function getDepositExpoImbalanceLimitBps() external view returns (int256 depositExpoImbalanceLimitBps_);

    /**
     * @notice Gets the expo imbalance limit when withdrawing assets (in basis points).
     * @return withdrawalExpoImbalanceLimitBps_ The withdrawal expo imbalance limit.
     */
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256 withdrawalExpoImbalanceLimitBps_);

    /**
     * @notice Gets the expo imbalance limit when opening a position (in basis points).
     * @return openExpoImbalanceLimitBps_ The open expo imbalance limit.
     */
    function getOpenExpoImbalanceLimitBps() external view returns (int256 openExpoImbalanceLimitBps_);

    /**
     * @notice Gets the expo imbalance limit when closing a position (in basis points).
     * @return closeExpoImbalanceLimitBps_ The close expo imbalance limit.
     */
    function getCloseExpoImbalanceLimitBps() external view returns (int256 closeExpoImbalanceLimitBps_);

    /**
     * @notice Returns the limit of the imbalance in bps to close the rebalancer position.
     * @return rebalancerCloseExpoImbalanceLimitBps_ The limit of the imbalance in bps to close the rebalancer position.
     */
    function getRebalancerCloseExpoImbalanceLimitBps()
        external
        view
        returns (int256 rebalancerCloseExpoImbalanceLimitBps_);

    /**
     * @notice Returns the imbalance desired on the long side after the creation of a rebalancer position.
     * @dev The creation of the rebalancer position aims for this target but does not guarantee reaching it.
     * @return targetLongImbalance_ The target long imbalance.
     */
    function getLongImbalanceTargetBps() external view returns (int256 targetLongImbalance_);

    /**
     * @notice Gets the nominal (target) price of USDN.
     * @return price_ The price of the USDN token after a rebase (in `_priceFeedDecimals`).
     */
    function getTargetUsdnPrice() external view returns (uint128 price_);

    /**
     * @notice Gets the USDN token price above which a rebase should occur.
     * @return threshold_ The rebase threshold (in `_priceFeedDecimals`).
     */
    function getUsdnRebaseThreshold() external view returns (uint128 threshold_);

    /**
     * @notice Gets the minimum collateral amount when opening a long position.
     * @return minLongPosition_ The minimum amount (with `_assetDecimals`).
     */
    function getMinLongPosition() external view returns (uint256 minLongPosition_);

    /* -------------------------------------------------------------------------- */
    /*                                State getters                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the value of the funding rate at the last timestamp (`getLastUpdateTimestamp`).
     * @return lastFunding_ The last value of the funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals.
     */
    function getLastFundingPerDay() external view returns (int256 lastFunding_);

    /**
     * @notice Gets the neutral price of the asset used during the last update of the vault and long balances.
     * @return lastPrice_ The most recent known price of the asset (in `_priceFeedDecimals`).
     */
    function getLastPrice() external view returns (uint128 lastPrice_);

    /**
     * @notice Gets the timestamp of the last time a fresh price was provided.
     * @return lastTimestamp_ The timestamp of the last update.
     */
    function getLastUpdateTimestamp() external view returns (uint128 lastTimestamp_);

    /**
     * @notice Gets the fees that were accumulated by the contract and are yet to be sent
     * to the fee collector (in `_assetDecimals`).
     * @return protocolFees_ The amount of accumulated fees still in the contract.
     */
    function getPendingProtocolFee() external view returns (uint256 protocolFees_);

    /**
     * @notice Gets the amount of assets backing the USDN token.
     * @return balanceVault_ The amount of assets on the vault side (in `_assetDecimals`).
     */
    function getBalanceVault() external view returns (uint256 balanceVault_);

    /**
     * @notice Gets the pending balance updates due to pending vault actions.
     * @return pendingBalanceVault_ The unreflected balance change due to pending vault actions (in `_assetDecimals`).
     */
    function getPendingBalanceVault() external view returns (int256 pendingBalanceVault_);

    /**
     * @notice Gets the exponential moving average of the funding rate per day.
     * @return ema_ The exponential moving average of the funding rate per day.
     */
    function getEMA() external view returns (int256 ema_);

    /**
     * @notice Gets the summed value of all the currently open long positions at `_lastUpdateTimestamp`.
     * @return balanceLong_ The balance of the long side (in `_assetDecimals`).
     */
    function getBalanceLong() external view returns (uint256 balanceLong_);

    /**
     * @notice Gets the total exposure of all currently open long positions.
     * @return totalExpo_ The total exposure of the longs (in `_assetDecimals`).
     */
    function getTotalExpo() external view returns (uint256 totalExpo_);

    /**
     * @notice Gets the accumulator used to calculate the liquidation multiplier.
     * @return accumulator_ The liquidation multiplier accumulator.
     */
    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory accumulator_);

    /**
     * @notice Gets the current version of the given tick.
     * @param tick The tick number.
     * @return tickVersion_ The version of the tick.
     */
    function getTickVersion(int24 tick) external view returns (uint256 tickVersion_);

    /**
     * @notice Gets the tick data for the current tick version.
     * @param tick The tick number.
     * @return tickData_ The tick data.
     */
    function getTickData(int24 tick) external view returns (TickData memory tickData_);

    /**
     * @notice Gets the long position at the provided tick and index.
     * @param tick The tick number.
     * @param index The position index.
     * @return position_ The long position.
     */
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory position_);

    /**
     * @notice Gets the highest tick that has an open position.
     * @return tick_ The highest populated tick.
     */
    function getHighestPopulatedTick() external view returns (int24 tick_);

    /**
     * @notice Gets the total number of long positions currently open.
     * @return totalLongPositions_ The number of long positions.
     */
    function getTotalLongPositions() external view returns (uint256 totalLongPositions_);

    /**
     * @notice Gets the address of the fallback contract.
     * @return fallback_ The address of the fallback contract.
     */
    function getFallbackAddress() external view returns (address fallback_);

    /**
     * @notice Gets the pause status of the USDN protocol.
     * @return isPaused_ True if it's paused, false otherwise.
     */
    function isPaused() external view returns (bool isPaused_);

    /**
     * @notice Gets the nonce a user can use to generate a delegation signature.
     * @dev This is to prevent replay attacks when using an eip712 delegation signature.
     * @param user The address of the user.
     * @return nonce_ The user's nonce.
     */
    function getNonce(address user) external view returns (uint256 nonce_);

    /* -------------------------------------------------------------------------- */
    /*                                   Setters                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Replaces the OracleMiddleware contract with a new implementation.
     * @dev Cannot be the 0 address.
     * @param newOracleMiddleware The address of the new contract.
     */
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external;

    /**
     * @notice Sets the fee collector address.
     * @dev  Cannot be the zero address.
     * @param newFeeCollector The address of the fee collector.
     */
    function setFeeCollector(address newFeeCollector) external;

    /**
     * @notice Replaces the LiquidationRewardsManager contract with a new implementation.
     * @dev Cannot be the 0 address.
     * @param newLiquidationRewardsManager The address of the new contract.
     */
    function setLiquidationRewardsManager(IBaseLiquidationRewardsManager newLiquidationRewardsManager) external;

    /**
     * @notice Replaces the Rebalancer contract with a new implementation.
     * @param newRebalancer The address of the new contract.
     */
    function setRebalancer(IBaseRebalancer newRebalancer) external;

    /**
     * @notice Sets the new deadlines of the exclusivity period for the validator to confirm its action and get its
     * security deposit back.
     * @param newLowLatencyValidatorDeadline The new exclusivity deadline for low-latency validation (offset from
     * initiate timestamp).
     * @param newOnChainValidatorDeadline The new exclusivity deadline for on-chain validation (offset from initiate
     * timestamp + oracle middleware's low latency delay).
     */
    function setValidatorDeadlines(uint128 newLowLatencyValidatorDeadline, uint128 newOnChainValidatorDeadline)
        external;

    /**
     * @notice Sets the minimum long position size.
     * @dev This value is used to prevent users from opening positions that are too small and not worth liquidating.
     * As this parameter highly depends on the value of the underlying asset, the max value for `newMinLongPosition` is
     * given as a constructor argument when the {UsdnProtocolFallback} contract is deployed, and is stored in an
     * immutable variable.
     * @param newMinLongPosition The new minimum long position size (with `_assetDecimals`).
     */
    function setMinLongPosition(uint256 newMinLongPosition) external;

    /**
     * @notice Sets the new minimum leverage for a position.
     * @param newMinLeverage The new minimum leverage.
     */
    function setMinLeverage(uint256 newMinLeverage) external;

    /**
     * @notice Sets the new maximum leverage for a position.
     * @param newMaxLeverage The new maximum leverage.
     */
    function setMaxLeverage(uint256 newMaxLeverage) external;

    /**
     * @notice Sets the new liquidation penalty (in ticks).
     * @param newLiquidationPenalty The new liquidation penalty.
     */
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external;

    /**
     * @notice Sets the new exponential moving average period of the funding rate.
     * @param newEMAPeriod The new EMA period.
     */
    function setEMAPeriod(uint128 newEMAPeriod) external;

    /**
     * @notice Sets the new scaling factor (SF) of the funding rate.
     * @param newFundingSF The new scaling factor (SF) of the funding rate.
     */
    function setFundingSF(uint256 newFundingSF) external;

    /**
     * @notice Sets the protocol fee.
     * @dev Fees are charged when the funding is applied (Example: 50 bps -> 0.5%).
     * @param newFeeBps The fee to be charged (in basis points).
     */
    function setProtocolFeeBps(uint16 newFeeBps) external;

    /**
     * @notice Sets the position fee.
     * @param newPositionFee The new position fee (in basis points).
     */
    function setPositionFeeBps(uint16 newPositionFee) external;

    /**
     * @notice Sets the vault fee.
     * @param newVaultFee The new vault fee (in basis points).
     */
    function setVaultFeeBps(uint16 newVaultFee) external;

    /**
     * @notice Sets the rewards ratio given to the caller when burning SDEX tokens.
     * @param newRewardsBps The new rewards ratio (in basis points).
     */
    function setSdexRewardsRatioBps(uint16 newRewardsBps) external;

    /**
     * @notice Sets the rebalancer bonus.
     * @param newBonus The bonus (in basis points).
     */
    function setRebalancerBonusBps(uint16 newBonus) external;

    /**
     * @notice Sets the ratio of SDEX tokens to burn per minted USDN.
     * @dev As this parameter highly depends on the value of the USDN token, the max value for `newRatio` is given as a
     * constructor argument when the {UsdnProtocolFallback} contract is deployed and is stored in an immutable variable.
     * @param newRatio The new ratio.
     */
    function setSdexBurnOnDepositRatio(uint32 newRatio) external;

    /**
     * @notice Sets the security deposit value.
     * @dev The maximum value of the security deposit is 2^64 - 1 = 18446744073709551615 = 18.4 ethers.
     * @param securityDepositValue The security deposit value.
     * This value cannot be greater than MAX_SECURITY_DEPOSIT.
     */
    function setSecurityDepositValue(uint64 securityDepositValue) external;

    /**
     * @notice Sets the imbalance limits (in basis point).
     * @dev `newLongImbalanceTargetBps` needs to be lower than `newCloseLimitBps` and
     * higher than the additive inverse of `newWithdrawalLimitBps`.
     * @param newOpenLimitBps The new open limit.
     * @param newDepositLimitBps The new deposit limit.
     * @param newWithdrawalLimitBps The new withdrawal limit.
     * @param newCloseLimitBps The new close limit.
     * @param newRebalancerCloseLimitBps The new rebalancer close limit.
     * @param newLongImbalanceTargetBps The new target imbalance limit for the long side.
     * A positive value will target below equilibrium, a negative one will target above equilibrium.
     * If negative, the rebalancerCloseLimit will be useless since the minimum value is 1.
     */
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        uint256 newRebalancerCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external;

    /**
     * @notice Sets the new safety margin for the liquidation price of newly open positions.
     * @param newSafetyMarginBps The new safety margin (in basis points).
     */
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external;

    /**
     * @notice Sets the new number of liquidations iteration for user actions.
     * @param newLiquidationIteration The new number of liquidation iteration.
     */
    function setLiquidationIteration(uint16 newLiquidationIteration) external;

    /**
     * @notice Sets the minimum amount of fees to be collected before they can be withdrawn.
     * @param newFeeThreshold The minimum amount of fees to be collected before they can be withdrawn.
     */
    function setFeeThreshold(uint256 newFeeThreshold) external;

    /**
     * @notice Sets the target USDN price.
     * @dev When a rebase of USDN occurs, it will bring the price back down to this value.
     * @param newPrice The new target price (with `_priceFeedDecimals`).
     * This value cannot be greater than `_usdnRebaseThreshold`.
     */
    function setTargetUsdnPrice(uint128 newPrice) external;

    /**
     * @notice Sets the USDN rebase threshold.
     * @dev When the price of USDN exceeds this value, a rebase will be triggered.
     * @param newThreshold The new threshold value (with `_priceFeedDecimals`).
     * This value cannot be smaller than `_targetUsdnPrice` or greater than uint128(2 * 10 ** s._priceFeedDecimals)
     */
    function setUsdnRebaseThreshold(uint128 newThreshold) external;

    /**
     * @notice Pauses related USDN protocol functions.
     * @dev Pauses simultaneously all initiate/validate, refundSecurityDeposit and transferPositionOwnership functions.
     * Before pausing, this function will call `_applyPnlAndFunding` with `_lastPrice` and the current timestamp.
     * This is done to stop the funding rate from accumulating while the protocol is paused. Be sure to call {unpause}
     * to update `_lastUpdateTimestamp` when unpausing.
     */
    function pause() external;

    /**
     * @notice Pauses related USDN protocol functions without applying PnLs and the funding.
     * @dev Pauses simultaneously all initiate/validate, refundSecurityDeposit and transferPositionOwnership functions.
     * This safe version will not call `_applyPnlAndFunding` before pausing.
     */
    function pauseSafe() external;

    /**
     * @notice Unpauses related USDN protocol functions.
     * @dev Unpauses simultaneously all initiate/validate, refundSecurityDeposit and transferPositionOwnership
     * functions. This function will set `_lastUpdateTimestamp` to the current timestamp to prevent any funding during
     * the pause. Only meant to be called after a {pause} call.
     */
    function unpause() external;

    /**
     * @notice Unpauses related USDN protocol functions without updating `_lastUpdateTimestamp`.
     * @dev Unpauses simultaneously all initiate/validate, refundSecurityDeposit and transferPositionOwnership
     * functions. This safe version will not set `_lastUpdateTimestamp` to the current timestamp.
     */
    function unpauseSafe() external;
}
