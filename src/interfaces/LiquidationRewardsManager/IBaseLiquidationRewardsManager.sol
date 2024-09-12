// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes as Types } from "../UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @notice This interface exposes the only function used by the UsdnProtocol
 * @dev Any future implementation of the rewards manager must implement this interface without modification
 */
interface IBaseLiquidationRewardsManager {
    /**
     * @notice Returns the amount of asset that needs to be sent to the liquidator
     * @param liquidatedTicks Information about the liquidated ticks
     * @param rebased Whether an optional USDN rebase was performed
     * @param rebalancerAction The `_triggerRebalancer` action
     * @param action The type of protocol action that triggered the liquidation
     * @param rebaseCallbackResult The result of the rebase callback, if any
     * @param priceData The oracle price data blob, if any. This can be used to reward users differently depending on
     * which oracle they have used to provide a liquidation price
     * @return assetRewards_ The asset tokens to send to the liquidator as rewards (in wei)
     */
    function getLiquidationRewards(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        Types.ProtocolAction action,
        bytes calldata rebaseCallbackResult,
        bytes calldata priceData
    ) external view returns (uint256 assetRewards_);
}
