// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";
import { IOrderManagerTypes } from "src/interfaces/OrderManager/IOrderManagerTypes.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

interface IOrderManager is IOrderManagerErrors, IOrderManagerEvents, IOrderManagerTypes {
    /// @notice Amount of decimals a multiplier has
    function MULTIPLIER_DECIMALS() external view returns (uint256);

    /// @notice Returns the address of the USDN protocol
    function getUsdnProtocol() external view returns (IUsdnProtocol);

    /**
     * @notice Deposit assets into this contract to be included in the next position
     * @dev If the user is already in a position, he needs to get out of it before adding more assets
     * @param amount The amount to deposit (in _assetDecimals)
     * @param to The address to assign the deposit to
     */
    function depositAssets(uint128 amount, address to) external;

    /**
     * @notice Withdraw assets if the user is not in a position yet
     * @dev If the entry position version of the user is lower than the current one, the transaction will revert
     * @param amount The amount to withdraw (in _assetDecimals)
     * @param to The address to send the assets to
     */
    function withdrawPendingAssets(uint128 amount, address to) external;

    /// @notice Returns the version of the current position (0 means no position open)
    function getCurrentPositionVersion() external view returns (uint128);

    /// @notice Returns the number of time the position of te order manager was liquidated
    function getLiquidationCount() external view returns (uint128);

    /// @notice Returns the data regarding the assets deposited by the provided user
    function getUserDepositData(address user) external view returns (UserDeposit memory userDeposit_);
}
