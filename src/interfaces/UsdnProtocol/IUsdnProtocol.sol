// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolActions } from "./IUsdnProtocolActions.sol";
import { IUsdnProtocolVault } from "./IUsdnProtocolVault.sol";
import { IUsdnProtocolLong } from "./IUsdnProtocolLong.sol";
import { IUsdnProtocolCore } from "./IUsdnProtocolCore.sol";
import { IUsdnProtocolStorage } from "./IUsdnProtocolStorage.sol";
import { IBaseOracleMiddleware } from "../OracleMiddleware/IBaseOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "../OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseRebalancer } from "../Rebalancer/IBaseRebalancer.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol
 */
interface IUsdnProtocol is
    IUsdnProtocolStorage,
    IUsdnProtocolActions,
    IUsdnProtocolVault,
    IUsdnProtocolLong,
    IUsdnProtocolCore
{
    /**
     * @notice Replace the OracleMiddleware contract with a new implementation
     * @dev Cannot be the 0 address
     * @param newOracleMiddleware The address of the new contract
     */
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external;

    /**
     * @notice Replace the LiquidationRewardsManager contract with a new implementation
     * @dev Cannot be the 0 address
     * @param newLiquidationRewardsManager The address of the new contract
     */
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external;

    /**
     * @notice Replace the Rebalancer contract with a new implementation
     * @param newRebalancer The address of the new contract
     */
    function setRebalancer(IBaseRebalancer newRebalancer) external;

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
     * @notice Set the new deadline for a user to confirm their action
     * @param newValidationDeadline The new deadline
     */
    function setValidationDeadline(uint256 newValidationDeadline) external;

    /**
     * @notice Set the new liquidation penalty (in tick spacing units)
     * @param newLiquidationPenalty The new liquidation penalty
     */
    function setLiquidationPenalty(uint8 newLiquidationPenalty) external;

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
     * @notice Set the minimum amount of fees to be collected before they can be withdrawn
     * @param newFeeThreshold The minimum amount of fees to be collected before they can be withdrawn
     */
    function setFeeThreshold(uint256 newFeeThreshold) external;

    /**
     * @notice Set the fee collector address
     * @param newFeeCollector The address of the fee collector
     * @dev The fee collector is the address that receives the fees charged by the protocol
     * The fee collector must be different from the zero address
     */
    function setFeeCollector(address newFeeCollector) external;

    /**
     * @notice Set imbalance limits basis point
     * @dev `newLongImbalanceTargetBps` needs to be lower than newCloseLimitBps and
     * higher than `- newWithdrawalLimitBps`
     * @param newOpenLimitBps The new open limit
     * @param newDepositLimitBps The new deposit limit
     * @param newWithdrawalLimitBps The new withdrawal limit
     * @param newCloseLimitBps The new close limit
     * @param newLongImbalanceTargetBps The new target imbalance limit for the long side
     * A positive value will target below equilibrium, a negative one will target above equilibrium
     */
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external;

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

    /**
     * @notice Set the minimum long position size
     * @dev This value is used to prevent users from opening positions that are too small and not worth liquidating
     * @param newMinLongPosition The new minimum long position, with _assetDecimals
     */
    function setMinLongPosition(uint256 newMinLongPosition) external;
}
