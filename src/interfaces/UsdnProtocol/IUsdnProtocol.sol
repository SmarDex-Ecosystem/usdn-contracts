// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IUsdnProtocolActions } from "src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol.
 */
interface IUsdnProtocol is IUsdnProtocolActions {
    /**
     * @notice Initialize the protocol, making a first deposit and creating a first long position.
     * @dev This function can only be called once, and no other user action can be performed until it was called.
     * Consult the current oracle middleware implementation to know the expected format for the price data, using the
     * `ProtocolAction.Initialize` action.
     * The price validation might require payment according to the return value of the `validationCost` function of the
     * middleware.
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

    /// @notice Set the new oracle middleware contract.
    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external;

    /// @notice Set the new minimum leverage for a position.
    function setMinLeverage(uint256 newMinLeverage) external;

    /// @notice Set the new maximum leverage for a position.
    function setMaxLeverage(uint256 newMaxLeverage) external;

    /// @notice Set the new deadline for a user to confirm their own action.
    function setValidationDeadline(uint256 newValidationDeadline) external;

    /// @notice Set the new funding rate per second.
    function setFundingRatePerSecond(int256 newFundingRatePerSecond) external;

    /// @notice Set the new liquidation penalty (in tick spacing units).
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external;

    /// @notice Set the new safety margin for the liquidation price of newly open positions.
    function setSafetyMargin(uint256 newSafetyMargin) external;

    /// @notice Set user current liquidation iteration in tick.
    function setLiquidationIteration(uint16 newLiquidationIteration) external;

    /// @notice Set new moving average period of the funding rate.
    function setEMAPeriod(uint128 newEMAPeriod) external;

    /// @notice Set the scaling factor (SF) of the funding rate.
    function setFundingSF(uint256 newFundingSF) external;
}
