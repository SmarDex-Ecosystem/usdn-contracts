// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { HugeUint } from "../../libraries/HugeUint.sol";
import { IBaseLiquidationRewardsManager } from "../OracleMiddleware/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "./IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "./IUsdnProtocolEvents.sol";

/**
 * @title IUsdnProtocolStorage
 * @notice Interface for the storage layer of the USDN protocol
 */
interface IUsdnProtocolStorage is IUsdnProtocolEvents, IUsdnProtocolErrors {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The setExternal role's signature
     * @return Get the role signature
     */
    function SET_EXTERNAL_ROLE() external pure returns (bytes32);

    /**
     * @notice The criticalFunctions role's signature
     * @return Get the role signature
     */
    function CRITICAL_FUNCTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The setProtocolParams role's signature
     * @return Get the role signature
     */
    function SET_PROTOCOL_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The setOptions role's signature
     * @return Get the role signature
     */
    function SET_OPTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetExternal role's signature
     * @return Get the role signature
     */
    function SET_USDN_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetExternal role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_EXTERNAL_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminCriticalFunctions role's signature
     * @return Get the role signature
     */
    function ADMIN_CRITICAL_FUNCTIONS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetProtocolParams role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_PROTOCOL_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetUsdnParams role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_USDN_PARAMS_ROLE() external pure returns (bytes32);

    /**
     * @notice The adminSetOptions role's signature
     * @return Get the role signature
     */
    function ADMIN_SET_OPTIONS_ROLE() external pure returns (bytes32);

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
     * @notice Get the minimum amount of wstETH for the initialization deposit and long
     * @return The minimum amount of wstETH
     */
    function MIN_INIT_DEPOSIT() external view returns (uint256);

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
     * 100 is equivalent to a 1% increase in liquidation price between ticks
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
     * @notice Get the amount of time a user can validate its action, after which other users can do it
     * and will claim the security deposit
     * @return The validation deadline (in seconds)
     */
    function getValidationDeadline() external view returns (uint256);

    /**
     * @notice Get the liquidation penalty applied to the liquidation price when opening a position
     * @return The liquidation penalty (in tick spacing units)
     */
    function getLiquidationPenalty() external view returns (uint8);

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
    function getTickData(int24 tick) external view returns (TickData memory);

    /**
     * @notice Get the long position at the provided tick, in the provided index
     * @param tick The tick number
     * @param index The position index
     * @return The long position
     */
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory);

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
}
