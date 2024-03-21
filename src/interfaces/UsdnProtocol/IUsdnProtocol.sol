// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolActions } from "src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol.
 */
interface IUsdnProtocol is IUsdnProtocolActions {
    /// @dev The minimum amount of wstETH for the initialization deposit and long.
    function MIN_INIT_DEPOSIT() external pure returns (uint256);

    /**
     * @notice Initialize the protocol, making a first deposit and creating a first long position.
     * @dev This function can only be called once, and no other user action can be performed until it was called.
     * Consult the current oracle middleware implementation to know the expected format for the price data, using the
     * `ProtocolAction.Initialize` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function of
     * the middleware.
     * @param depositAmount the amount of wstETH for the deposit.
     * @param longAmount the amount of wstETH for the long.
     * @param desiredLiqPrice the desired liquidation price for the long.
     * @param currentPriceData the current price data.
     */
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable;

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
}
