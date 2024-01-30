// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolCore
 * @notice Interface for the core layer of the USDN protocol.
 */
interface IUsdnProtocolCore {
    /// @notice The address that holds the minimum supply of USDN and first minimum long position.
    function DEAD_ADDRESS() external view returns (address);

    /// @notice The default max number of iterations for the checking the pending actions queue
    function DEFAULT_QUEUE_MAX_ITER() external view returns (uint256);

    /**
     * @notice Get the predicted value of the liquidation price multiplier for the given asset price and timestamp
     * @dev The effect of the funding rates since the last contract state update are taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     */
    function getLiquidationMultiplier(uint128 currentPrice, uint128 timestamp) external view returns (uint256);

    /**
     * @notice Get the predicted value of the funding for the given asset price and timestamp
     * @dev The effect of any profits or losses from the long positions since the last contract state update are taken
     * into account.
     * @dev When multiplied with the long trading exposure, this value gives the asset balance that needs to be paid to
     * the vault side (or long side if negative).
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return fund_ The magnitude of the funding (with `FUNDING_RATE_DECIMALS` decimals)
     * @return longExpo_ The long trading exposure (with asset decimals)
     * @return vaultExpo_ The vault trading exposure (with asset decimals)
     */
    function funding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 fund_, int256 longExpo_, int256 vaultExpo_);

    /**
     * @notice Get the predicted value of the funding (in asset units) for the given asset price and timestamp
     * @dev The effect of any profits or losses from the long positions since the last contract state update are taken
     * into account.
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return fund_ The number of asset tokens of funding (with asset decimals)
     * @return longExpo_ The long trading exposure (with asset decimals)
     * @return vaultExpo_ The vault trading exposure (with asset decimals)
     */
    function fundingAsset(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 fund_, int256 longExpo_, int256 vaultExpo_);

    /**
     * @notice Get the predicted value of the long balance for the given asset price and timestamp
     * @dev The effect of the funding rates and any profit or loss of the long positions since the last contract state
     * update are taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     */
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Get the predicted value of the vault balance for the given asset price and timestamp
     * @dev The effect of the funding rates and any profit or loss of the long positions since the last contract state
     * update are taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     */
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Get the predicted value of the long trading exposure for the given asset price and timestamp
     * @dev The effect of the funding rates and any profit or loss of the long positions since the last contract state
     * update are taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     */
    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Get the predicted value of the vault trading exposure for the given asset price and timestamp
     * @dev The effect of the funding rates and any profit or loss of the long positions since the last contract state
     * update are taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     */
    function vaultTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    /**
     * @notice Update the contract state (balances of the long and vault sides) according to the effects of the funding
     * rates and any profit or loss of the long positions since the last contract state update.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.None` action.
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @param priceData The current price data for the asset.
     */
    function updateBalances(bytes calldata priceData) external payable;

    /**
     * @notice Retrieve a pending action that must be validated by the next user action in the protocol.
     * @dev If this function returns a pending action, then the next user action MUST include the price update data
     * for this pending action as the last parameter.
     * @param maxIter The maximum number of iterations to find the first initialized item
     * @return action_ The pending action if any, otherwise a struct with all fields set to zero and ProtocolAction.None
     */
    function getActionablePendingAction(uint256 maxIter) external returns (PendingAction memory action_);
}
