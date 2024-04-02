// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

interface IOrderManager is IOrderManagerErrors, IOrderManagerEvents {
    /**
     * @notice The accumulated data of all the orders in a tick.
     * @param amountOfAssets The amount of assets in the tick.
     * @param longPositionTick The tick of the long position if created, otherwise equal to PENDING_ORDERS_TICK.
     * @param longPositionTickVersion The tick version of the long position.
     * @param longPositionIndex The index of the long position in the USDN protocol tick array.
     */
    struct OrdersDataInTick {
        uint232 amountOfAssets;
        int24 longPositionTick;
        uint256 longPositionTickVersion;
        uint256 longPositionIndex;
    }

    /// @notice Tick indicating the orders are not used in a position yet.
    function PENDING_ORDERS_TICK() external pure returns (int24);

    /**
     * @notice Returns the amount of assets a user has in a tick.
     * @param tick The tick the order is in.
     * @param tickVersion The tick version.
     * @param user The address of the user.
     * @return The amount of assets a user has in a tick
     */
    function getUserAmountInTick(int24 tick, uint256 tickVersion, address user) external view returns (uint232);

    /**
     * @notice Returns the accumulated data of all the orders in a tick.
     * @param tick The tick the orders are in.
     * @param tickVersion The tick version.
     * @return ordersData_ The data of the orders in the tick.
     */
    function getOrdersDataInTick(int24 tick, uint256 tickVersion)
        external
        view
        returns (OrdersDataInTick memory ordersData_);

    /// @notice Returns the address of the USDN protocol.
    function getUsdnProtocol() external view returns (IUsdnProtocol);

    /// @notice Set the maximum approval for the USDN protocol to take assets from this contract.
    function approveAssetsForSpending(uint256 allowance) external;

    /**
     * @notice Deposit the provided amount of assets to the provided tick
     * and transfer the assets from the user to this contract.
     * @dev This function will always use the latest version of the provided tick.
     * @param tick The tick to add the order in.
     * @param amount The amount of assets to deposit.
     */
    function depositAssetsInTick(int24 tick, uint232 amount) external;

    /**
     * @notice Withdraw an amount of the user's assets from the provided tick and send them back to him.
     * @dev This function will always use the latest version of the provided tick.
     * @param tick The tick to remove the order from.
     * @param amountToWithdraw The amount of assets to withdraw.
     */
    function withdrawAssetsFromTick(int24 tick, uint232 amountToWithdraw) external;
}
