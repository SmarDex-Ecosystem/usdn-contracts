// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IRebalancerErrors } from "src/interfaces/Rebalancer/IRebalancerErrors.sol";
import { IRebalancerEvents } from "src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerTypes } from "src/interfaces/Rebalancer/IRebalancerTypes.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

interface IRebalancer is IRebalancerErrors, IRebalancerEvents, IRebalancerTypes {
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
    function getPendingAssetsAmount() external view returns (uint256);

    /**
     * @notice Returns the max leverage a position can have
     * @dev Returns the max leverage of the USDN Protocol if it's lower than the rebalancer's
     * @return maxLeverage_ The max leverage a position can have
     */
    function getPositionMaxLeverage() external view returns (uint256 maxLeverage_);

    /**
     * @notice Update the max leverage a position can have
     * @dev `newMaxLeverage` must be between the min and max leverage of the USDN protocol
     * @param newMaxLeverage The new max leverage
     */
    function setPositionMaxLeverage(uint256 newMaxLeverage) external;

    /**
     * @notice Returns the minimum amount of assets to be deposited by a user
     * @return The minimum amount of assets to be deposited by a user
     */
    function getMinAssetDeposit() external view returns (uint256);

    /**
     * @notice Sets the minimum amount of assets to be deposited by a user
     * @dev The new minimum amount must be greater than or equal to the minimum long position of the USDN protocol
     * @param minAssetDeposit The new minimum amount of assets to be deposited
     */
    function setMinAssetDeposit(uint256 minAssetDeposit) external;

    /**
     * @notice Returns the data regarding the assets deposited by the provided user
     * @param user The address of the user
     * @return The data regarding the assets deposited by the provided user
     */
    function getUserDepositData(address user) external view returns (UserDeposit memory);

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
}
