// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolCore } from "src/interfaces/UsdnProtocol/IUsdnProtocolCore.sol";

/**
 * @title IUsdnProtocolVault
 * @notice Interface for the vault layer of the USDN protocol
 */
interface IUsdnProtocolVault is IUsdnProtocolCore {
    /**
     * @notice Get the predicted value of the USDN token price for the given asset price and timestamp
     * @dev The effect of the funding rates and any profit or loss of the long positions since the last contract state
     * update is taken into account
     * @param currentPrice The current or predicted asset price
     * @param timestamp The timestamp corresponding to `currentPrice`
     * @return The predicted value of the USDN token price
     */
    function usdnPrice(uint128 currentPrice, uint128 timestamp) external view returns (uint256);

    /**
     * @notice Get the value of the USDN token price for the given asset price and the current timestamp
     * @dev The effect of the funding rates and any profit or loss of the long positions since the last contract state
     * update is taken into account
     * @param currentPrice The most recent/current asset price
     * @return The value of the USDN token price
     */
    function usdnPrice(uint128 currentPrice) external view returns (uint256);

    /**
     * @notice Calculate an estimation of assets received when withdrawing
     * @param usdnShares The amount of USDN shares
     * @param price The price of the asset
     * @param timestamp The timestamp of the operation
     * @return assetExpected_ The expected amount of assets to be received
     */
    function previewWithdraw(uint256 usdnShares, uint256 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_);
}
