// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IRebalancerErrors } from "src/interfaces/Rebalancer/IRebalancerErrors.sol";
import { IRebalancerEvents } from "src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerTypes } from "src/interfaces/Rebalancer/IRebalancerTypes.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

interface IRebalancer is IRebalancerErrors, IRebalancerEvents, IRebalancerTypes {
    /// @notice Returns the address of the USDN protocol
    function getUsdnProtocol() external view returns (IUsdnProtocol);

    /// @notice Returns the minimum amount of assets to be deposited by a user
    function getMinAssetDeposit() external view returns (uint256);

    /**
     * @notice Sets the minimum amount of assets to be deposited by a user
     * @param minAssetDeposit The new minimum amount of assets to be deposited
     */
    function setMinAssetDeposit(uint256 minAssetDeposit) external;

    /**
     * @notice Deposit assets into this contract to be included in the next position
     * @dev If `to` is already in a position, they need to close it completely before adding more assets
     * @param amount The amount to deposit (in _assetDecimals)
     * @param to The address to assign the deposit to
     */
    function depositAssets(uint128 amount, address to) external;

    /**
     * @notice Withdraw assets if the user is not in a position yet
     * @dev If the entry position version of the user is lower than or equal to the current one,
     * the transaction will revert
     * @param amount The amount to withdraw (in _assetDecimals)
     * @param to The address to send the assets to
     */
    function withdrawPendingAssets(uint128 amount, address to) external;

    /// @notice Returns the version of the current position (0 means no position open)
    function getPositionVersion() external view returns (uint128);

    /// @notice Returns the data regarding the assets deposited by the provided user
    function getUserDepositData(address user) external view returns (UserDeposit memory userDeposit_);
}
