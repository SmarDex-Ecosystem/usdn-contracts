// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";

/**
 * @title IUsdnProtocolParams
 * @notice Interface for the params of the USDN protocol.
 */
interface IUsdnProtocolParams is IUsdnProtocolEvents, IUsdnProtocolErrors {
    error UsdnProtocolParamsAlreadyInitialized();

    function initialize(
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        address feeCollector,
        uint8 leverageDecimals,
        uint8 fundingSfDecimals,
        uint8 priceFeedDecimals,
        uint16 maxLiquidationIteration
    ) external;

    /* -------------------------------------------------------------------------- */
    /*                          Pseudo-constants getters                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Divisor for the bps values
     * @dev Example: 200 -> 2%
     */
    function BPS_DIVISOR() external pure returns (uint256);

    function getLeverageDecimals() external view returns (uint8);

    function getFundingSfDecimals() external view returns (uint8);

    function getPriceFeedDecimals() external view returns (uint8);

    function getMaxLiquidationIteration() external view returns (uint16);

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /// @notice The oracle middleware contract.
    function getOracleMiddleware() external view returns (IOracleMiddleware);

    /// @notice The liquidation rewards manager contract
    function getLiquidationRewardsManager() external view returns (ILiquidationRewardsManager);

    /// @notice The minimum leverage for a position
    function getMinLeverage() external view returns (uint256);

    /// @notice The maximum leverage value
    function getMaxLeverage() external view returns (uint256);

    /// @notice The deadline for a user to confirm their own action
    function getValidationDeadline() external view returns (uint256);

    /// @notice The liquidation penalty (in tick spacing units)
    function getLiquidationPenalty() external view returns (uint24);

    /// @notice Safety margin for the liquidation price of newly open positions
    function getSafetyMarginBps() external view returns (uint256);

    /// @notice User current liquidation iteration in tick.
    function getLiquidationIteration() external view returns (uint16);

    /// @notice The moving average period of the funding rate
    function getEMAPeriod() external view returns (uint128);

    /// @notice The scaling factor (SF) of the funding rate
    function getFundingSF() external view returns (uint256);

    /// @notice The protocol fee in bps
    function getProtocolFeeBps() external view returns (uint16);

    /// @notice The position fee in bps
    function getPositionFeeBps() external view returns (uint16);

    /// @notice The fee threshold before fees are sent to the fee collector
    function getFeeThreshold() external view returns (uint256);

    /// @notice The address of the fee collector
    function getFeeCollector() external view returns (address);

    /// @notice The address of the fee collector
    function getMiddlewareValidationDelay() external view returns (uint256);

    /// @notice The nominal (target) price of USDN (with _priceFeedDecimals)
    function getTargetUsdnPrice() external view returns (uint128);

    /// @notice The USDN price threshold to trigger a rebase (with _priceFeedDecimals)
    function getUsdnRebaseThreshold() external view returns (uint128);

    /// @notice The interval between two automatic rebase checks
    function getUsdnRebaseInterval() external view returns (uint256);

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

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Replace the OracleMiddleware contract with a new implementation.
     * @dev Cannot be the 0 address.
     * @param newOracleMiddleware the address of the new contract.
     */
    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external;

    /**
     * @notice Replace the LiquidationRewardsManager contract with a new implementation.
     * @dev Cannot be the 0 address.
     * @param newLiquidationRewardsManager the address of the new contract.
     */
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external;

    /// @notice Set the new minimum leverage for a position.
    function setMinLeverage(uint256 newMinLeverage) external;

    /// @notice Set the new maximum leverage for a position.
    function setMaxLeverage(uint256 newMaxLeverage) external;

    /// @notice Set the new deadline for a user to confirm their own action.
    function setValidationDeadline(uint256 newValidationDeadline) external;

    /// @notice Set the new liquidation penalty (in tick spacing units).
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external;

    /// @notice Set the new safety margin bps for the liquidation price of newly open positions.
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external;

    /// @notice Set the new user current liquidation iteration in tick.
    function setLiquidationIteration(uint16 newLiquidationIteration) external;

    /// @notice Set the new exponential moving average period of the funding rate.
    function setEMAPeriod(uint128 newEMAPeriod) external;

    /// @notice Set the new scaling factor (SF) of the funding rate.
    function setFundingSF(uint256 newFundingSF) external;

    /**
     * @notice Set the fee basis points.
     * @param newFeeBps The fee bps to be charged.
     * @dev Fees are charged when transfers occur between the vault and the long
     * example: 50 bps -> 0.5%
     */
    function setProtocolFeeBps(uint16 newFeeBps) external;

    /**
     * @notice Update the position fees.
     * @param newPositionFee The new position fee (in basis points).
     */
    function setPositionFeeBps(uint16 newPositionFee) external;

    /**
     * @notice Set the minimum amount of fees to be collected before they can be withdrawn
     * @param newFeeThreshold The minimum amount of fees to be collected before they can be withdrawn
     */
    function setFeeThreshold(uint256 newFeeThreshold) external;

    /**
     * @notice Set the fee collector address.
     * @param newFeeCollector The address of the fee collector.
     * @dev The fee collector is the address that receives the fees charged by the protocol
     * The fee collector must be different from the zero address
     */
    function setFeeCollector(address newFeeCollector) external;

    /**
     * @notice Set the target USDN price
     * @param newPrice The new target price (with _priceFeedDecimals)
     * @dev When a rebase of USDN occurs, it will bring the price back down to this value.
     * This value cannot be greater than `_usdnRebaseThreshold`.
     */
    function setTargetUsdnPrice(uint128 newPrice) external;

    /**
     * @notice Set the USDN rebase threshold
     * @param newThreshold The new threshold value (with _priceFeedDecimals)
     * @dev When the price of USDN exceeds this value, a rebase might be triggered.
     * This value cannot be smaller than `_targetUsdnPrice`.
     */
    function setUsdnRebaseThreshold(uint128 newThreshold) external;

    /**
     * @notice Set the USDN rebase interval
     * @param newInterval The new interval duration
     * @dev When the duration since the last rebase check exceeds this value, a rebase check will be performed.
     * When calling `liquidate`, this limit is ignored and the check is always performed.
     */
    function setUsdnRebaseInterval(uint256 newInterval) external;

    /**
     * @notice Set imbalance limits basis point
     * @param newOpenLimitBps The new open limit
     * @param newDepositLimitBps The new deposit limit
     * @param newWithdrawalLimitBps The new withdrawal limit
     * @param newCloseLimitBps The new close limit
     */
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps
    ) external;
}
