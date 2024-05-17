// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IRebalancerErrors } from "src/interfaces/Rebalancer/IRebalancerErrors.sol";
import { IRebalancerEvents } from "src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerTypes } from "src/interfaces/Rebalancer/IRebalancerTypes.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

interface IRebalancer is IRebalancerErrors, IRebalancerEvents, IRebalancerTypes {
    /**
     * @notice Returns the address of the USDN protocol
     * @return usdnProtocol_ The address of the USDN protocol
     */
    function getUsdnProtocol() external view returns (IUsdnProtocol usdnProtocol_);

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

    /**
     * @notice Returns the version of the current position (0 means no position open)
     * @return positionVersion_ The current position version
     */
    function getPositionVersion() external view returns (uint128 positionVersion_);

    /**
     * @notice Returns the version of the last position that got liquidated
     * @dev 0 means no liquidated version yet
     * @return The version of the last position that got liquidated
     */
    function getLastLiquidatedVersion() external view returns (uint128);

    /**
     * @notice Returns the data regarding the assets deposited by the provided user
     * @return userDeposit_ The data regarding the assets deposited by the user
     */
    function getUserDepositData(address user) external view returns (UserDeposit memory userDeposit_);
}
