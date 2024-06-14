// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IRebalancerErrors } from "./IRebalancerErrors.sol";
import { IRebalancerEvents } from "./IRebalancerEvents.sol";
import { IRebalancerTypes } from "./IRebalancerTypes.sol";
import { PositionId, PreviousActionsData } from "../UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocol } from "../UsdnProtocol/IUsdnProtocol.sol";

interface IRebalancer is IRebalancerErrors, IRebalancerEvents, IRebalancerTypes {
    /**
     * @notice The value of the multiplier at 1x
     * @dev Also helps to normalize the result of multiplier calculations
     * @return The multiplier factor
     */
    function MULTIPLIER_FACTOR() external view returns (uint256);

    /**
     * @notice Returns the address of the asset used by the USDN protocol
     * @return The address of the asset used by the USDN protocol
     */
    function getAsset() external view returns (IERC20Metadata);

    /**
     * @notice Returns the address of the USDN protocol
     * @return The address of the USDN protocol
     */
    function getUsdnProtocol() external view returns (IUsdnProtocol);

    /**
     * @notice Returns the version of the current position (0 means no position open)
     * @return The version of the current position
     */
    function getPositionVersion() external view returns (uint128);

    /**
     * @notice Returns the amount of assets deposited and waiting for the next version to be opened
     * @return The amount of pending assets
     */
    function getPendingAssetsAmount() external view returns (uint128);

    /**
     * @notice Returns the maximum leverage a position can have
     * @dev Returns the max leverage of the USDN Protocol if it's lower than the rebalancer's
     * @return maxLeverage_ The max leverage a position can have
     */
    function getPositionMaxLeverage() external view returns (uint256 maxLeverage_);

    /**
     * @notice Returns the necessary data for the USDN protocol to update the position
     * @return pendingAssets_ The amount of assets pending
     * @return maxLeverage_ The max leverage of the rebalancer
     * @return currentPosId_ The ID of the current position (tick == NO_POSITION_TICK if no position)
     */
    function getCurrentStateData()
        external
        view
        returns (uint128 pendingAssets_, uint256 maxLeverage_, PositionId memory currentPosId_);

    /**
     * @notice Returns the minimum amount of assets to be deposited by a user
     * @return The minimum amount of assets to be deposited by a user
     */
    function getMinAssetDeposit() external view returns (uint256);

    /**
     * @notice Returns the data of the provided version of the position
     * @param version The version of the position
     * @return positionData_ The date for the provided version of the position
     */
    function getPositionData(uint128 version) external view returns (PositionData memory positionData_);

    /**
     * @notice Returns the limit of the imbalance in bps to close the position
     * @return The limit of the imbalance in bps to close the position
     */
    function getCloseImbalanceLimitBps() external view returns (uint256);

    /**
     * @notice Returns the data regarding the assets deposited by the provided user
     * @param user The address of the user
     * @return The data regarding the assets deposited by the provided user
     */
    function getUserDepositData(address user) external view returns (UserDeposit memory);

    /**
     * @notice Increase the allowance of assets for the USDN protocol spender by `addAllowance`
     * @param addAllowance Amount to add to the allowance of the UsdnProtocol contract
     */
    function increaseAssetAllowance(uint256 addAllowance) external;

    /**
     * @notice Deposit assets into this contract to be included in the next position
     * @dev If `to` is already in a position, they need to close it completely before adding more assets
     * @param amount The amount to deposit (in _assetDecimals)
     * @param to The address to assign the deposit to
     */
    function depositAssets(uint128 amount, address to) external;

    /**
     * @notice Returns the version of the last position that got liquidated
     * @dev 0 means no liquidated version yet
     * @return The version of the last position that got liquidated
     */
    function getLastLiquidatedVersion() external view returns (uint128);

    /**
     * @notice Withdraw assets if the user is not in a position yet
     * @dev If the entry position version of the user is lower than or equal to the current one,
     * the transaction will revert
     * @param amount The amount to withdraw (in _assetDecimals)
     * @param to The address to send the assets to
     */
    function withdrawPendingAssets(uint128 amount, address to) external;

    /**
     * @notice Indicates that the previous version of the position was closed and a new one was opened
     * @dev If `previousPosValue` equals 0, it means the previous version got liquidated
     * @param newPosId The position ID of the new position
     * @param previousPosValue The amount of assets left in the previous position
     */
    function updatePosition(PositionId calldata newPosId, uint128 previousPosValue) external;

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Update the max leverage a position can have
     * @dev `newMaxLeverage` must be between the min and max leverage of the USDN protocol
     * This function can only be called by the owner
     * @param newMaxLeverage The new max leverage
     */
    function setPositionMaxLeverage(uint256 newMaxLeverage) external;

    /**
     * @notice Sets the minimum amount of assets to be deposited by a user
     * @dev The new minimum amount must be greater than or equal to the minimum long position of the USDN protocol
     * This function can only be called by the owner or the USDN protocol
     * @param minAssetDeposit The new minimum amount of assets to be deposited
     */
    function setMinAssetDeposit(uint256 minAssetDeposit) external;

    /**
     * @notice Sets the limit of the imbalance in bps to close the position
     * @dev This function can only be called by the owner
     * If the new limit is greater than the `_closeExpoImbalanceLimitBps` setting in the USDN protocol,
     * this new limit will be ineffective
     * @param closeImbalanceLimitBps The new limit of the imbalance in bps to close the position
     */
    function setCloseImbalanceLimitBps(uint256 closeImbalanceLimitBps) external;

    /**
     * @notice Close a user deposited amount of the rebalancer current position in the UsdnProtocol
     * @dev The rebalancer allow partial close of the user deposited asset. It should still
     * have `_minAssetDeposit` user amount deposited in the rebalancer.
     * @param amount The amount to close (in rebalancer deposited ratio)
     * @param to The to address
     * @param validator The validator address
     * @param currentPriceData The current price data
     * @param previousActionsData The previous action price data
     * @return success_ If the UsdnProtocol `initiateClosePosition` was successful
     */
    function initiateClosePosition(
        uint128 amount,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);
}
