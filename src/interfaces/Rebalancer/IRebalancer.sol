// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseRebalancer } from "./IBaseRebalancer.sol";
import { IRebalancerErrors } from "./IRebalancerErrors.sol";
import { IRebalancerEvents } from "./IRebalancerEvents.sol";
import { IRebalancerTypes } from "./IRebalancerTypes.sol";
import { PreviousActionsData } from "../UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocol } from "../UsdnProtocol/IUsdnProtocol.sol";

interface IRebalancer is IBaseRebalancer, IRebalancerErrors, IRebalancerEvents, IRebalancerTypes {
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
     * @notice Returns the maximum leverage a position can have
     * @dev Returns the max leverage of the USDN Protocol if it's lower than the rebalancer's
     * @return maxLeverage_ The max leverage a position can have
     */
    function getPositionMaxLeverage() external view returns (uint256 maxLeverage_);

    /**
     * @notice Returns the amount of assets deposited and waiting for the next version to be opened
     * @return The amount of pending assets
     */
    function getPendingAssetsAmount() external view returns (uint128);

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
     * @notice Get the time limits for the action validation process
     * @return The time limits
     */
    function getTimeLimits() external view returns (TimeLimits memory);

    /**
     * @notice Increase the allowance of assets for the USDN protocol spender by `addAllowance`
     * @param addAllowance Amount to add to the allowance of the UsdnProtocol contract
     */
    function increaseAssetAllowance(uint256 addAllowance) external;

    /**
     * @notice Returns the version of the last position that got liquidated
     * @dev 0 means no liquidated version yet
     * @return The version of the last position that got liquidated
     */
    function getLastLiquidatedVersion() external view returns (uint128);

    /**
     * @notice Deposit assets into this contract to be included in the next position after validation
     * @dev The user must call `validateDepositAssets` between `_timeLimits.validationDelay` and
     * `_timeLimits.validationDeadline` seconds after this action
     * @param amount The amount in assets that will be deposited into the Rebalancer
     * @param to The address which will need to validate and which will own the position
     */
    function initiateDepositAssets(uint88 amount, address to) external;

    /**
     * @notice Validate a deposit to be included in the next position version
     * @dev The `to` from the `initiateDepositAssets` must call this function between `_timeLimits.validationDelay` and
     * `_timeLimits.validationDeadline` seconds after the initiate action
     */
    function validateDepositAssets() external;

    /**
     * @notice Retrieve the assets for a failed deposit due to waiting too long before calling `validateDepositAssets`
     * @dev The user must wait `_timeLimits.actionCooldown` since the `initiateDepositAssets` before calling this
     * function
     */
    function resetDepositAssets() external;

    /**
     * @notice Withdraw assets if the user is not in a position yet
     * @dev If the entry position version of the user is lower than or equal to the current one,
     * the transaction will revert
     * @param amount The amount to withdraw (in _assetDecimals)
     * @param to The address to send the assets to
     */
    function withdrawPendingAssets(uint88 amount, address to) external;

    /**
     * @notice Closes a user deposited amount of the current UsdnProtocol rebalancer position
     * @dev The rebalancer allows partially closing its position to withdraw the user's assets + PnL
     * The remaining amount needs to be above `_minAssetDeposit` and `_minLongPosition` on the USDN protocol side
     * @param amount The amount to close relative to the amount deposited
     * @param to The to address
     * @param validator The validator address
     * @param currentPriceData The current price data
     * @param previousActionsData The previous action price data
     * @return success_ If the UsdnProtocol's `initiateClosePosition` was successful
     * If false, the action failed because of pending liquidations, check IUsdnProtocolActions:initiateClosePosition for
     * more details
     */
    function initiateClosePosition(
        uint88 amount,
        address payable to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external payable returns (bool success_);

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
     * @notice Sets the limit of the imbalance in bps to close the position
     * @dev This function can only be called by the owner
     * If the new limit is greater than the `_closeExpoImbalanceLimitBps` setting in the USDN protocol,
     * this new limit will be ineffective
     * @param closeImbalanceLimitBps The new limit of the imbalance in bps to close the position
     */
    function setCloseImbalanceLimitBps(uint256 closeImbalanceLimitBps) external;

    /**
     * @notice Set the various time limits in seconds
     * @param validationDelay The validation delay
     * @param validationDeadline The validation deadline
     * @param actionCooldown The cooldown period duration
     */
    function setTimeLimits(uint80 validationDelay, uint80 validationDeadline, uint80 actionCooldown) external;
}
