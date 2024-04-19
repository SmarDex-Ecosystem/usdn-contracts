// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { Position, PendingAction, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";

/**
 * @title IUsdnProtocolStorage
 * @notice Interface for the storage layer of the USDN protocol
 */
interface IUsdnProtocolStorage is IUsdnProtocolEvents, IUsdnProtocolErrors {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the number of decimals of the leverage of a position
     * @return The leverage's number of decimals
     */
    function LEVERAGE_DECIMALS() external pure returns (uint8);

    /**
     * @notice Get the number of decimals of the funding rate
     * @return The funding rate's number of decimals
     */
    function FUNDING_RATE_DECIMALS() external pure returns (uint8);

    /**
     * @notice Get the number of decimals of tokens used in the protocol (except the asset)
     * @return The tokens' amount of decimals
     */
    function TOKENS_DECIMALS() external pure returns (uint8);

    /**
     * @notice Get the number of decimals of the liquidation multiplier
     * @return The liquidation multiplier's number of decimals
     */
    function LIQUIDATION_MULTIPLIER_DECIMALS() external pure returns (uint8);

    /**
     * @notice Get the number of decimals of the scaling factor of the funding rate
     * @return The scaling factor's number of decimals
     */
    function FUNDING_SF_DECIMALS() external pure returns (uint8);

    /**
     * @notice Get the divisor for the ratio of USDN to SDEX to burn on deposit
     * @return The USDN to SDEX burn ratio divisor
     */
    function SDEX_BURN_ON_DEPOSIT_DIVISOR() external pure returns (uint256);

    /**
     * @notice Get the factor to convert the security deposit value to an uint24
     * @return The security deposit factor
     */
    function SECURITY_DEPOSIT_FACTOR() external pure returns (uint128);

    /**
     * @notice Get the divisor for basis point values
     * @dev Example: 200 -> 2%
     * @return The basis points divisor
     */
    function BPS_DIVISOR() external pure returns (uint256);

    /**
     * @notice Get the maximum number of liquidations that can be done per call
     * @return The maximum number of iterations
     */
    function MAX_LIQUIDATION_ITERATION() external pure returns (uint16);

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables getters                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The liquidation tick spacing for storing long positions
     * @dev A tick spacing of 1 is equivalent to a 0.01% increase in liquidation price between ticks. A tick spacing of
     * 100 is equivalent to a 1% increase in liquidation price between ticks.
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
     * @notice Get the amount of decimals the price feed for the asset has
     * @return The amount of decimals of the price feed
     */
    function getPriceFeedDecimals() external view returns (uint8);

    /**
     * @notice Get the amount of decimals the asset ERC20 token has
     * @return The amount of decimals for the asset
     */
    function getAssetDecimals() external view returns (uint8);

    /**
     * @notice Get the USDN ERC20 token contract
     * @return The USDN ERC20 token contract
     */
    function getUsdn() external view returns (IUsdn);

    /**
     * @notice Get the MIN_DIVISOR constant of the USDN token
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
    function getOracleMiddleware() external view returns (IOracleMiddleware);

    /**
     * @notice Get the liquidation rewards manager contract
     * @return The address of the liquidation rewards manager contract
     */
    function getLiquidationRewardsManager() external view returns (ILiquidationRewardsManager);

    /**
     * @notice Get the order manager contract
     * @return The address of the order manager contract
     */
    function getOrderManager() external view returns (IOrderManager);

    /**
     * @notice Get the minimum leverage an opened position can have
     * @return The minimum leverage (with LEVERAGE_DECIMALS decimals)
     */
    function getMinLeverage() external view returns (uint256);

    /**
     * @notice Get the maximum leverage an opened position can have
     * @dev A position can have a leverage a bit higher than this value under specific conditions involving
     * a change to the liquidation penalty setting
     * @return The maximum leverage value (with LEVERAGE_DECIMALS decimals)
     */
    function getMaxLeverage() external view returns (uint256);

    /**
     * @notice Get the amount of time a user can validate its own action, after which other users can do it
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
     * @notice Get the number of iterations to do when attempting to liquidate positions during user actions
     * @return The number of iterations
     */
    function getLiquidationIteration() external view returns (uint16);

    /**
     * @notice Get the amount of time elapsed after which the EMA is set to the
     * last funding rate during a balance update
     * @return The time elapsed (in seconds)
     */
    function getEMAPeriod() external view returns (uint128);

    /**
     * @notice Get The scaling factor (SF) of the funding rate
     * @return The scaling factor
     */
    function getFundingSF() external view returns (uint256);

    /**
     * @notice Get the fee the protocol takes during the application of funding rates
     * @return The fee (in basis points)
     */
    function getProtocolFeeBps() external view returns (uint16);

    /**
     * @notice Get the fee applied when a position is opened
     * @return The position fee (in basis points)
     */
    function getPositionFeeBps() external view returns (uint16);

    /**
     * @notice Get the ratio of USDN to SDEX tokens to burn on deposit
     * @return The ratio (to be divided by SDEX_BURN_ON_DEPOSIT_DIVISOR)
     */
    function getSdexBurnOnDepositRatio() external view returns (uint32);

    /**
     * @notice Get the security deposit required for the open a new position
     * @return The amount of assets to use as a security deposit (in ether)
     */
    function getSecurityDepositValue() external view returns (uint256);

    /**
     * @notice Get the threshold before fees are sent to the fee collector
     * @return The amount of fees to be accumulated (in assets decimals)
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
     * @notice Get expo imbalance limits (in basis points)
     * @return openExpoImbalanceLimitBps_ The open expo imbalance limit
     * @return depositExpoImbalanceLimitBps_ The deposit expo imbalance limit
     * @return withdrawalExpoImbalanceLimitBps_ The withdrawal expo imbalance limit
     * @return closeExpoImbalanceLimitBps_ The close expo imbalance limit
     */
    function getExpoImbalanceLimits()
        external
        view
        returns (
            int256 openExpoImbalanceLimitBps_,
            int256 depositExpoImbalanceLimitBps_,
            int256 withdrawalExpoImbalanceLimitBps_,
            int256 closeExpoImbalanceLimitBps_
        );

    /**
     * @notice Get the nominal (target) price of USDN
     * @return The price of the USDN token after a rebase (with _priceFeedDecimals)
     */
    function getTargetUsdnPrice() external view returns (uint128);

    /**
     * @notice Get the USDN token price at which a rebase should occur
     * @return The rebase threshold (with _priceFeedDecimals)
     */
    function getUsdnRebaseThreshold() external view returns (uint128);

    /**
     * @notice Get the interval between two automatic rebase checks
     * @return The interval between 2 rebase checks (in seconds)
     */
    function getUsdnRebaseInterval() external view returns (uint256);

    /**
     * @notice Get the minimum value of a long position to be opened's collateral (in USD)
     * @return The minimum value (with _priceFeedDecimals)
     */
    function getMinLongPosition() external view returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                                    State getters                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the funding rate the last time it was calculated (getLastUpdateTimestamp)
     * @return The last value of the funding rate
     */
    function getLastFunding() external view returns (int256);

    /**
     * @notice Get the price of the asset during the last update of the vault and long balances
     * @return The price of the asset (with price feed decimals)
     */
    function getLastPrice() external view returns (uint128);

    /**
     * @notice Get the timestamp of the last time we updated the vault and long balances according to the PnL and the
     * fundings
     * @return The timestamp of the last update
     */
    function getLastUpdateTimestamp() external view returns (uint128);

    /**
     * @notice Get the multiplier for liquidation price calculations
     * @return The current value of the liquidation multiplier
     */
    function getLiquidationMultiplier() external view returns (uint256);

    /**
     * @notice Get the fees that were accumulated by the contract and are yet to be sent to the fee collector
     * (in assets decimals)
     * @return The amount of assets accumulated as fees still in the contract
     */
    function getPendingProtocolFee() external view returns (uint256);

    /**
     * @notice Get the pending action of the user (1 per user max)
     * @dev The value stored is an index into the `pendingActionsQueue` deque, shifted by one. A value of 0 means no
     * pending action. Since the deque uses uint128 indices, the highest index will not overflow when adding one.
     * @param user The user address
     * @return The pending action of the user (if there is one)
     */
    function getPendingAction(address user) external view returns (uint256);

    /**
     * @notice Get the pending action at the provided index of the pending queue
     * @param index The index in the queue
     * @return The pending action
     */
    function getPendingActionAt(uint256 index) external view returns (PendingAction memory);

    /**
     * @notice Get the amount of assets backing the USDN token
     * @return The amount of assets on the vault side (with asset decimals)
     */
    function getBalanceVault() external view returns (uint256);

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
     * @return The amount of collateral used in the protocol (with asset decimals)
     */
    function getBalanceLong() external view returns (uint256);

    /**
     * @notice Get the total exposure of all the currently open long positions
     * @return The total exposure of the longs (with asset decimals)
     */
    function getTotalExpo() external view returns (uint256);

    /**
     * @notice Get the current version of the tick
     * @param tick The tick
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
     * @param tick The tick
     * @param index The position index
     * @return The long position
     */
    function getCurrentLongPosition(int24 tick, uint256 index) external view returns (Position memory);

    /**
     * @notice Get the highest tick that has an opened position
     * @return The highest populated tick
     */
    function getMaxInitializedTick() external view returns (int24);

    /**
     * @notice Get the total number of long positions currently open
     * @return The number of long positions
     */
    function getTotalLongPositions() external view returns (uint256);

    /**
     * @notice Get the hash generated from the tick and a version
     * @param tick The tick number
     * @param version The tick version
     * @return The hash of the tick and version
     */
    function tickHash(int24 tick, uint256 version) external pure returns (bytes32);
}
