// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes as Types } from "../UsdnProtocol/IUsdnProtocolTypes.sol";
import { IRebalancerTypes } from "./IRebalancerTypes.sol";

interface IBaseRebalancer {
    /**
     * @notice Returns the necessary data for the USDN protocol to update the position.
     * @return pendingAssets_ The amount of assets that are pending inclusion in the protocol.
     * @return maxLeverage_ The maximum leverage of the rebalancer.
     * @return currentPosId_ The ID of the current position (`tick` == `NO_POSITION_TICK` if no position).
     */
    function getCurrentStateData()
        external
        view
        returns (uint128 pendingAssets_, uint256 maxLeverage_, Types.PositionId memory currentPosId_);

    /**
     * @notice Returns the minimum amount of assets a user can deposit in the rebalancer.
     * @return minAssetDeposit_ The minimum amount of assets that can be deposited by a user.
     */
    function getMinAssetDeposit() external view returns (uint256 minAssetDeposit_);

    /**
     * @notice Returns the data regarding the assets deposited by the provided user.
     * @param user The address of the user.
     * @return data_ The data regarding the assets deposited by the provided user.
     */
    function getUserDepositData(address user) external view returns (IRebalancerTypes.UserDeposit memory data_);

    /**
     * @notice Indicates that the previous version of the position was closed and a new one was opened.
     * @dev If `previousPosValue` equals 0, it means the previous version got liquidated.
     * @param newPosId The position ID of the new position.
     * @param previousPosValue The amount of assets left in the previous position.
     */
    function updatePosition(Types.PositionId calldata newPosId, uint128 previousPosValue) external;

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Sets the minimum amount of assets to be deposited by a user.
     * @dev The new minimum amount must be greater than or equal to the minimum long position of the USDN protocol.
     * This function can only be called by the owner or the USDN protocol.
     * @param minAssetDeposit The new minimum amount of assets to be deposited.
     */
    function setMinAssetDeposit(uint256 minAssetDeposit) external;
}
