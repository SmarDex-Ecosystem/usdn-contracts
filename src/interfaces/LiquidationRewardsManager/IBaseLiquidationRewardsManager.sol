// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes as Types } from "../UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @notice This interface exposes the only function used by the UsdnProtocol
 * @dev Future implementations of the rewards manager must implement this interface without modifications.
 */
interface IBaseLiquidationRewardsManager {
    /**
     * @notice Computes the amount of assets to reward a liquidator.
     * @param liquidatedTicks Information about the liquidated ticks.
     * @param currentPrice The current price of the asset.
     * @param rebased Indicates whether a USDN rebase was performed.
     * @param rebalancerAction The action performed by the {IUsdnProtocolLongLibrary._triggerRebalancer} function.
     * @param action The type of protocol action that triggered the liquidation.
     * @param rebaseCallbackResult The result of the rebase callback, if any.
     * @param priceData The oracle price data, if any. This can be used to differentiate rewards based on the oracle
     * used to provide the liquidation price.
     * @return assetRewards_ The amount of asset tokens to reward the liquidator.
     */
    function getLiquidationRewards(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        uint256 currentPrice,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        Types.ProtocolAction action,
        bytes calldata rebaseCallbackResult,
        bytes calldata priceData
    ) external view returns (uint256 assetRewards_);
}
