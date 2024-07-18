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
     * @notice Get the divisor for the ratio of USDN to SDEX to burn on deposit
     * @return The USDN to SDEX burn ratio divisor
     */
    function SDEX_BURN_ON_DEPOSIT_DIVISOR() external view returns (uint256);

    /**
     * @notice Get the sentinel value indicating that a `PositionId` represents no position
     * @return The tick value for a `PositionId` that represents no position
     */
    function NO_POSITION_TICK() external view returns (int24);

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
     * @notice Get the USDN ERC20 token contract
     * @return The USDN ERC20 token contract
     */
    function getUsdn() external view returns (IUsdn);

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
     * @notice Get edge values for the position
     * @return minLeverage_ The minimum leverage value to open a position, with `LEVERAGE_DECIMALS` decimals
     * @return maxLeverage_ The highest leverage value to open a position, with `LEVERAGE_DECIMALS` decimals (A position
     * can have a leverage a bit higher than this value under specific conditions involving a change to the liquidation
     * penalty setting)
     * @return minLongPosition_ The minimum amount of collateral to open a long position (in `_assetDecimals`)
     */
    function getEdgePositionValues()
        external
        view
        returns (uint256 minLeverage_, uint256 maxLeverage_, uint256 minLongPosition_);

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
     * @notice Get all the fees information of the protocol
     * @return protocolFeeBps_ The fee taken by the protocol during the application of funding (in basis points)
     * @return positionFeeBps_ The fee taken when a long position is opened or closed (in basis points)
     * @return vaultFeeBps_ The fee taken when a deposit or withdrawal is made to the vault (in basis points)
     * @return feeThreshold_ The threshold before fees are sent to the fee collector (in `_assetDecimals`)
     * @return pendingProtocolFee_ The amount of assets accumulated as fees still in the contract (in `_assetDecimals`)
     * @return feeCollector_ The address of the fee collector
     */
    function getFeesInfo()
        external
        view
        returns (
            uint16 protocolFeeBps_,
            uint16 positionFeeBps_,
            uint16 vaultFeeBps_,
            uint256 feeThreshold_,
            uint256 pendingProtocolFee_,
            address feeCollector_
        );

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
     * @notice Get the limits for the imbalance of the protocol when depositing, withdrawing, opening, and closing
     * (in basis points)
     * @return depositExpoImbalanceLimitBps_ The deposit expo imbalance limit
     * @return withdrawalExpoImbalanceLimitBps_ The withdrawal expo imbalance limit
     * @return openExpoImbalanceLimitBps_ The open expo imbalance limit
     * @return closeExpoImbalanceLimitBps_ The close expo imbalance limit
     * @return longImbalanceTargetBps_ The target imbalance to have on the long side after the creation of a rebalancer
     * position (the creation of the rebalancer position aims for this target but does not guarantee to hit it)
     */
    function getExpoImbalanceLimits()
        external
        view
        returns (
            int256 depositExpoImbalanceLimitBps_,
            int256 withdrawalExpoImbalanceLimitBps_,
            int256 openExpoImbalanceLimitBps_,
            int256 closeExpoImbalanceLimitBps_,
            int256 longImbalanceTargetBps_
        );

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
