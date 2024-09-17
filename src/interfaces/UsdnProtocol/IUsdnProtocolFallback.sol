// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { HugeUint } from "../../libraries/HugeUint.sol";
import { IBaseLiquidationRewardsManager } from "../OracleMiddleware/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../Usdn/IUsdn.sol";
import { IUsdnProtocolTypes as Types } from "./IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolFallback
 * @notice Interface for the USDN protocol fallback functions
 */
interface IUsdnProtocolFallback {
    /**
     * @notice Calculate an estimation of assets received when withdrawing
     * @param usdnShares The amount of USDN shares
     * @param price The price of the asset
     * @param timestamp The timestamp of the operation
     * @return assetExpected_ The expected amount of assets to be received
     */
    function previewWithdraw(uint256 usdnShares, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_);

    /**
     * @notice Calculate an estimation of USDN tokens to be minted and SDEX tokens to be burned for a deposit
     * @param amount The amount of assets of the pending deposit
     * @param price The price of the asset at the time of the last update
     * @param timestamp The timestamp of the operation
     * @return usdnSharesExpected_ The amount of USDN shares to be minted
     * @return sdexToBurn_ The amount of SDEX tokens to be burned
     */
    function previewDeposit(uint256 amount, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_);

    /**
     * @notice Refund the security deposit to a validator of a liquidated initiated long position
     * @param validator The address of the validator
     * @dev The security deposit is always sent to the validator
     */
    function refundSecurityDeposit(address payable validator) external;

    /* -------------------------------------------------------------------------- */
    /*                               Admin functions                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Remove a stuck pending action and perform the minimal amount of cleanup necessary
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly
     * @param validator The address of the validator
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn)
     */
    function removeBlockedPendingAction(address validator, address payable to) external;

    /**
     * @notice Remove a stuck pending action with no cleanup
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly
     * Always try to use `removeBlockedPendingAction` first, and only call this function if the other one fails
     * @param validator The address of the validator
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn)
     */
    function removeBlockedPendingActionNoCleanup(address validator, address payable to) external;

    /**
     * @notice Remove a stuck pending action and perform the minimal amount of cleanup necessary
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly
     * @param rawIndex The raw index of the pending action in the queue
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn)
     */
    function removeBlockedPendingAction(uint128 rawIndex, address payable to) external;

    /**
     * @notice Remove a stuck pending action with no cleanup
     * @dev This function can only be called by the owner of the protocol, it serves as an escape hatch if a
     * pending action ever gets stuck due to something internal reverting unexpectedly
     * Always try to use `removeBlockedPendingAction` first, and only call this function if the other one fails
     * @param rawIndex The raw index of the pending action in the queue
     * @param to Where the retrieved funds should be sent (security deposit, assets, usdn)
     */
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to) external;

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the number of decimals of a position's leverage
     * @return The leverage's number of decimals
     */
    function LEVERAGE_DECIMALS() external view returns (uint8);

    /**
     * @notice Get the number of decimals of the funding rate
     * @return The funding rate's number of decimals
     */
    function FUNDING_RATE_DECIMALS() external view returns (uint8);

    /**
     * @notice Get the number of decimals of tokens used in the protocol (except the asset)
     * @return The tokens' number of decimals
     */
    function TOKENS_DECIMALS() external view returns (uint8);

    /**
     * @notice Get the number of decimals used for the fixed representation of the liquidation multiplier
     * @return The liquidation multiplier's number of decimals
     */
    function LIQUIDATION_MULTIPLIER_DECIMALS() external view returns (uint8);

    /**
     * @notice Get the number of decimals in the scaling factor of the funding rate
     * @return The scaling factor's number of decimals
     */
    function FUNDING_SF_DECIMALS() external view returns (uint8);

    /**
     * @notice Get the divisor for the ratio of USDN to SDEX to burn on deposit
     * @return The USDN to SDEX burn ratio divisor
     */
    function SDEX_BURN_ON_DEPOSIT_DIVISOR() external view returns (uint256);

    /**
     * @notice Get the divisor for basis point values
     * @dev Example: 200 -> 2%
     * @return The basis points divisor
     */
    function BPS_DIVISOR() external view returns (uint256);

    /**
     * @notice Get the maximum number of tick liquidations that can be done per call
     * @return The maximum number of iterations
     */
    function MAX_LIQUIDATION_ITERATION() external view returns (uint16);

    /**
     * @notice Get the sentinel value indicating that a `PositionId` represents no position
     * @return The tick value for a `PositionId` that represents no position
     */
    function NO_POSITION_TICK() external view returns (int24);

    /**
     * @notice The minimum total supply of USDN that we allow
     * @dev Upon the first deposit, this amount is sent to the dead address and cannot be later recovered
     * @return The minimum total supply of USDN
     */
    function MIN_USDN_SUPPLY() external view returns (uint256);

    /**
     * @notice The address that holds the minimum supply of USDN and the first minimum long position
     * @return The address
     */
    function DEAD_ADDRESS() external view returns (address);

    /**
     * @notice The maximum number of actionable pending action items returned by `getActionablePendingActions`
     * @return The maximum value
     */
    function MAX_ACTIONABLE_PENDING_ACTIONS() external pure returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables getters                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The liquidation tick spacing for storing long positions
     * @dev A tick spacing of 1 is equivalent to a 0.01% increase in liquidation price between ticks. A tick spacing of
     * 100 is equivalent to a ~1.005% increase in liquidation price between ticks
     * @return The tick spacing
     */
    function getTickSpacing() external view returns (int24);

    /**
     * @notice Get the asset ERC20 token contract
     * @return The asset ERC20 token contract
     */
    function getAsset() external view returns (IERC20Metadata);

    /**
     * @notice Get the SDEX ERC20 token contract
     * @return The SDEX ERC20 token contract
     */
    function getSdex() external view returns (IERC20Metadata);

    /**
     * @notice Get the number of decimals the price feed for the asset has
     * @return The number of decimals of the price feed
     */
    function getPriceFeedDecimals() external view returns (uint8);

    /**
     * @notice Get the number of decimals the asset ERC20 token has
     * @return The number of decimals for the asset
     */
    function getAssetDecimals() external view returns (uint8);

    /**
     * @notice Get the USDN ERC20 token contract
     * @return The USDN ERC20 token contract
     */
    function getUsdn() external view returns (IUsdn);

    /**
     * @notice Get the MIN_DIVISOR constant of the USDN token
     * @dev Check the USDN contract for more information
     * @return The MIN_DIVISOR constant of the USDN token
     */
    function getUsdnMinDivisor() external view returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the oracle middleware contract
     * @return The address of the oracle middleware contract
     */
    function getOracleMiddleware() external view returns (IBaseOracleMiddleware);

    /**
     * @notice Get the liquidation rewards manager contract
     * @return The address of the liquidation rewards manager contract
     */
    function getLiquidationRewardsManager() external view returns (IBaseLiquidationRewardsManager);

    /**
     * @notice Get the rebalancer contract
     * @return The address of the rebalancer contract
     */
    function getRebalancer() external view returns (IBaseRebalancer);

    /**
     * @notice Get the lowest leverage used to open a position
     * @return The minimum leverage (with `LEVERAGE_DECIMALS` decimals)
     */
    function getMinLeverage() external view returns (uint256);

    /**
     * @notice Get the highest leverage used to open a position
     * @dev A position can have a leverage a bit higher than this value under specific conditions involving
     * a change to the liquidation penalty setting
     * @return The maximum leverage value (with `LEVERAGE_DECIMALS` decimals)
     */
    function getMaxLeverage() external view returns (uint256);

    /**
     * @notice The deadline for a user to confirm their action with a low-latency oracle
     * @dev After this deadline, any user can validate the action with the low-latency oracle until the
     * OracleMiddleware's `_lowLatencyDelay`, and retrieve the security deposit for the pending action
     * @return The low-latency validation deadline (in seconds)
     */
    function getLowLatencyValidatorDeadline() external view returns (uint128);

    /**
     * @notice The deadline for a user to confirm their action with the on-chain oracle
     * @dev After this deadline, any user can validate the action with the on-chain oracle and retrieve the security
     * deposit for the pending action
     * @return The on-chain validation deadline (in seconds)
     */
    function getOnChainValidatorDeadline() external view returns (uint128);

    /**
     * @notice Get the liquidation penalty applied to the liquidation price when opening a position
     * @return The liquidation penalty (in ticks)
     */
    function getLiquidationPenalty() external view returns (uint24);

    /**
     * @notice Get the safety margin for the liquidation price of newly open positions
     * @return The safety margin (in basis points)
     */
    function getSafetyMarginBps() external view returns (uint256);

    /**
     * @notice Get the number of tick liquidations to do when attempting to liquidate positions during user actions
     * @return The number of iterations
     */
    function getLiquidationIteration() external view returns (uint16);

    /**
     * @notice The time frame for the EMA calculations
     * @dev The EMA is set to the last funding rate when the time elapsed between 2 actions is greater than this value
     * @return The time elapsed (in seconds)
     */
    function getEMAPeriod() external view returns (uint128);

    /**
     * @notice Get The scaling factor (SF) of the funding rate
     * @return The scaling factor
     */
    function getFundingSF() external view returns (uint256);

    /**
     * @notice Get the fee taken by the protocol during the application of funding
     * @return The fee (in basis points)
     */
    function getProtocolFeeBps() external view returns (uint16);

    /**
     * @notice Get the fee applied when a long position is opened or closed
     * @return The position fee (in basis points)
     */
    function getPositionFeeBps() external view returns (uint16);

    /**
     * @notice Get the fee applied during a vault deposit or withdrawal
     * @return The action fee (in basis points)
     */
    function getVaultFeeBps() external view returns (uint16);

    /**
     * @notice Get the part of the remaining collateral that is given as a bonus
     * to the Rebalancer upon liquidation of a tick
     * @return The collateral bonus for the Rebalancer (in basis points)
     */
    function getRebalancerBonusBps() external view returns (uint16);

    /**
     * @notice Get the ratio of USDN to SDEX tokens to burn on deposit
     * @return The ratio (to be divided by SDEX_BURN_ON_DEPOSIT_DIVISOR)
     */
    function getSdexBurnOnDepositRatio() external view returns (uint32);

    /**
     * @notice Get the security deposit required to open a new position
     * @return The amount of assets to use as a security deposit (in ether)
     */
    function getSecurityDepositValue() external view returns (uint64);

    /**
     * @notice Get the threshold before fees are sent to the fee collector
     * @return The amount of fees to be accumulated (in `_assetDecimals`)
     */
    function getFeeThreshold() external view returns (uint256);

    /**
     * @notice Get the address of the fee collector
     * @return The address of the fee collector
     */
    function getFeeCollector() external view returns (address);

    /**
     * @notice Returns the delay between the moment an action is initiated and
     * the timestamp of the price data used to validate that action
     * @return The delay (in seconds)
     */
    function getMiddlewareValidationDelay() external view returns (uint256);

    /**
     * @notice Get the expo imbalance limit when depositing assets (in basis points)
     * @return depositExpoImbalanceLimitBps_ The deposit expo imbalance limit
     */
    function getDepositExpoImbalanceLimitBps() external view returns (int256 depositExpoImbalanceLimitBps_);

    /**
     * @notice Get the expo imbalance limit when withdrawing assets (in basis points)
     * @return withdrawalExpoImbalanceLimitBps_ The withdrawal expo imbalance limit
     */
    function getWithdrawalExpoImbalanceLimitBps() external view returns (int256 withdrawalExpoImbalanceLimitBps_);

    /**
     * @notice Get the expo imbalance limit when opening a position (in basis points)
     * @return openExpoImbalanceLimitBps_ The open expo imbalance limit
     */
    function getOpenExpoImbalanceLimitBps() external view returns (int256 openExpoImbalanceLimitBps_);

    /**
     * @notice Get the expo imbalance limit when closing a position (in basis points)
     * @return closeExpoImbalanceLimitBps_ The close expo imbalance limit
     */
    function getCloseExpoImbalanceLimitBps() external view returns (int256 closeExpoImbalanceLimitBps_);

    /**
     * @notice Returns the limit of the imbalance in bps to close the rebalancer position
     * @return rebalancerCloseExpoImbalanceLimitBps_ The limit of the imbalance in bps to close the rebalancer position
     */
    function getRebalancerCloseExpoImbalanceLimitBps()
        external
        view
        returns (int256 rebalancerCloseExpoImbalanceLimitBps_);

    /**
     * @notice Returns the target imbalance to have on the long side after the creation of a rebalancer position
     * @dev The creation of the rebalancer position aims for this target but does not guarantee to hit it
     * @return targetLongImbalance_ The target long imbalance
     */
    function getLongImbalanceTargetBps() external view returns (int256 targetLongImbalance_);

    /**
     * @notice Get the nominal (target) price of USDN
     * @return The price of the USDN token after a rebase (in _priceFeedDecimals)
     */
    function getTargetUsdnPrice() external view returns (uint128);

    /**
     * @notice Get the USDN token price at which a rebase should occur
     * @return The rebase threshold (in _priceFeedDecimals)
     */
    function getUsdnRebaseThreshold() external view returns (uint128);

    /**
     * @notice Get the interval between two automatic rebase checks
     * @return The interval between 2 rebase checks (in seconds)
     */
    function getUsdnRebaseInterval() external view returns (uint256);

    /**
     * @notice Get the minimum collateral amount when opening a long position
     * @return The minimum amount (with `_assetDecimals`)
     */
    function getMinLongPosition() external view returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the value of the funding rate at the last timestamp (`getLastUpdateTimestamp`)
     * @return The last value of the funding rate (per day) with `FUNDING_RATE_DECIMALS` decimals
     */
    function getLastFundingPerDay() external view returns (int256);

    /**
     * @notice Get the price of the asset during the last update of the vault and long balances
     * @return The price of the asset (in `_priceFeedDecimals`)
     */
    function getLastPrice() external view returns (uint128);

    /**
     * @notice Get the timestamp of the last time a fresh price was provided
     * @return The timestamp of the last update
     */
    function getLastUpdateTimestamp() external view returns (uint128);

    /**
     * @notice Get the fees that were accumulated by the contract and are yet to be sent to the fee collector
     * (in `_assetDecimals`)
     * @return The amount of assets accumulated as fees still in the contract
     */
    function getPendingProtocolFee() external view returns (uint256);

    /**
     * @notice Get the amount of assets backing the USDN token
     * @return The amount of assets on the vault side (in `_assetDecimals`)
     */
    function getBalanceVault() external view returns (uint256);

    /**
     * @notice Get the pending balance updates due to pending vault actions
     * @return The unreflected balance change due to pending vault actions (in `_assetDecimals`)
     */
    function getPendingBalanceVault() external view returns (int256);

    /**
     * @notice Get the timestamp when the last USDN rebase check was performed
     * @return The timestamp of the last USDN rebase check
     */
    function getLastRebaseCheck() external view returns (uint256);

    /**
     * @notice Get the exponential moving average of the funding
     * @return The exponential moving average of the funding
     */
    function getEMA() external view returns (int256);

    /**
     * @notice Get the amount of collateral used by all the currently open long positions
     * @return The amount of collateral used in the protocol (in `_assetDecimals`)
     */
    function getBalanceLong() external view returns (uint256);

    /**
     * @notice Get the total exposure of all currently open long positions
     * @return The total exposure of the longs (in `_assetDecimals`)
     */
    function getTotalExpo() external view returns (uint256);

    /**
     * @notice The accumulator used to calculate the liquidation multiplier
     * @return The liquidation multiplier accumulator
     */
    function getLiqMultiplierAccumulator() external view returns (HugeUint.Uint512 memory);

    /**
     * @notice Get the current version of the tick
     * @param tick The tick number
     * @return The version of the tick
     */
    function getTickVersion(int24 tick) external view returns (uint256);

    /**
     * @notice Get the tick data for the current tick version
     * @param tick The tick number
     * @return The tick data
     */
    function getTickData(int24 tick) external view returns (Types.TickData memory);

    /**
     * @notice Get the long position at the provided tick, in the provided index
     * @param tick The tick number
     * @param index The position index
     * @return The long position
     */
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Types.Position memory);

    /**
     * @notice Get the highest tick that has an open position
     * @return The highest populated tick
     */
    function getHighestPopulatedTick() external view returns (int24);

    /**
     * @notice Get the total number of long positions currently open
     * @return The number of long positions
     */
    function getTotalLongPositions() external view returns (uint256);

    /**
     * @notice Get the address of the contract that handles the setters
     * @return The address of the setters contract
     */
    function getFallbackAddress() external view returns (address);

    /* -------------------------------------------------------------------------- */
    /*                                   Setters                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Replace the OracleMiddleware contract with a new implementation
     * @dev Cannot be the 0 address
     * @param newOracleMiddleware The address of the new contract
     */
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external;

    /**
     * @notice Set the fee collector address
     * @param newFeeCollector The address of the fee collector
     * @dev The fee collector is the address that receives the fees charged by the protocol
     * The fee collector must be different from the zero address
     */
    function setFeeCollector(address newFeeCollector) external;

    /**
     * @notice Replace the LiquidationRewardsManager contract with a new implementation
     * @dev Cannot be the 0 address
     * @param newLiquidationRewardsManager The address of the new contract
     */
    function setLiquidationRewardsManager(IBaseLiquidationRewardsManager newLiquidationRewardsManager) external;

    /**
     * @notice Replace the Rebalancer contract with a new implementation
     * @param newRebalancer The address of the new contract
     */
    function setRebalancer(IBaseRebalancer newRebalancer) external;

    /**
     * @notice Set the new deadlines for a user to confirm their action
     * @param newLowLatencyValidatorDeadline The new deadline for low-latency validation (offset from initiate
     * timestamp)
     * @param newOnChainValidatorDeadline The new deadline for on-chain validation (offset from initiate timestamp +
     * oracle middleware's low latency delay)
     */
    function setValidatorDeadlines(uint128 newLowLatencyValidatorDeadline, uint128 newOnChainValidatorDeadline)
        external;

    /**
     * @notice Set the minimum long position size
     * @dev This value is used to prevent users from opening positions that are too small and not worth liquidating
     * @param newMinLongPosition The new minimum long position, with _assetDecimals
     */
    function setMinLongPosition(uint256 newMinLongPosition) external;

    /**
     * @notice Set the new minimum leverage for a position
     * @param newMinLeverage The new minimum leverage
     */
    function setMinLeverage(uint256 newMinLeverage) external;

    /**
     * @notice Set the new maximum leverage for a position
     * @param newMaxLeverage The new maximum leverage
     */
    function setMaxLeverage(uint256 newMaxLeverage) external;

    /**
     * @notice Set the new liquidation penalty (in ticks)
     * @param newLiquidationPenalty The new liquidation penalty
     */
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external;

    /**
     * @notice Set the new exponential moving average period of the funding rate
     * @param newEMAPeriod The new EMA period
     */
    function setEMAPeriod(uint128 newEMAPeriod) external;

    /**
     * @notice Set the new scaling factor (SF) of the funding rate
     * @param newFundingSF The new scaling factor (SF) of the funding rate
     */
    function setFundingSF(uint256 newFundingSF) external;

    /**
     * @notice Set the fee basis points
     * @param newFeeBps The fee bps to be charged
     * @dev Fees are charged when transfers occur between the vault and the long
     * Example: 50 bps -> 0.5%
     */
    function setProtocolFeeBps(uint16 newFeeBps) external;

    /**
     * @notice Update the position fee
     * @param newPositionFee The new position fee (in basis points)
     */
    function setPositionFeeBps(uint16 newPositionFee) external;

    /**
     * @notice Update the vault fee
     * @param newVaultFee The new vault fee (in basis points)
     */
    function setVaultFeeBps(uint16 newVaultFee) external;

    /**
     * @notice Update the rebalancer bonus
     * @param newBonus The bonus (in basis points)
     */
    function setRebalancerBonusBps(uint16 newBonus) external;

    /**
     * @notice Update the ratio of USDN to SDEX tokens to burn on deposit
     * @param newRatio The new ratio
     */
    function setSdexBurnOnDepositRatio(uint32 newRatio) external;

    /**
     * @notice Set the security deposit value
     * @dev The maximum value of the security deposit is 2^64 - 1 = 18446744073709551615 = 18.4 ethers
     * @param securityDepositValue The security deposit value
     */
    function setSecurityDepositValue(uint64 securityDepositValue) external;

    /**
     * @notice Set imbalance limits basis point
     * @dev `newLongImbalanceTargetBps` needs to be lower than newCloseLimitBps and
     * higher than `- newWithdrawalLimitBps`
     * @param newOpenLimitBps The new open limit
     * @param newDepositLimitBps The new deposit limit
     * @param newWithdrawalLimitBps The new withdrawal limit
     * @param newCloseLimitBps The new close limit
     * @param newRebalancerCloseLimitBps The new rebalancer close limit
     * @param newLongImbalanceTargetBps The new target imbalance limit for the long side
     * A positive value will target below equilibrium, a negative one will target above equilibrium
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
     * @notice Set the new safety margin bps for the liquidation price of newly open positions
     * @param newSafetyMarginBps The new safety margin bps
     */
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external;

    /**
     * @notice Set the new user's current liquidation iteration in the tick
     * @param newLiquidationIteration The new number of liquidation iteration
     */
    function setLiquidationIteration(uint16 newLiquidationIteration) external;

    /**
     * @notice Set the minimum amount of fees to be collected before they can be withdrawn
     * @param newFeeThreshold The minimum amount of fees to be collected before they can be withdrawn
     */
    function setFeeThreshold(uint256 newFeeThreshold) external;

    /**
     * @notice Set the target USDN price
     * @param newPrice The new target price (with _priceFeedDecimals)
     * @dev When a rebase of USDN occurs, it will bring the price back down to this value
     * This value cannot be greater than `_usdnRebaseThreshold`
     */
    function setTargetUsdnPrice(uint128 newPrice) external;

    /**
     * @notice Set the USDN rebase threshold
     * @param newThreshold The new threshold value (with _priceFeedDecimals)
     * @dev When the price of USDN exceeds this value, a rebase might be triggered
     * This value cannot be smaller than `_targetUsdnPrice`
     */
    function setUsdnRebaseThreshold(uint128 newThreshold) external;

    /**
     * @notice Set the USDN rebase interval
     * @param newInterval The new interval duration
     * @dev When the duration since the last rebase check exceeds this value, a rebase check will be performed
     * When calling `liquidate`, this limit is ignored and the check is always performed
     */
    function setUsdnRebaseInterval(uint256 newInterval) external;
}
