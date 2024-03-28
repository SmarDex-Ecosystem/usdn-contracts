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

    /**
     * @notice Information about an order.
     * @param user The address of the user.
     * @param amountOfAssets The amount of assets in the order.
     */
    struct Order {
        address user;
        uint96 amountOfAssets;
    }

    /// @notice Tick indicating the orders are still pending
    function PENDING_ORDERS_TICK() external pure returns (int24);

    /**
     * @notice Returns The order at the index of the array of orders in the provided tick.
     * @param tick The tick the order is in.
     * @param tickVersion The tick version.
     * @param index The index in the order array.
     * @return order_ The order in the provided tick and index.
     */
    function getOrderInTickAtIndex(int24 tick, uint256 tickVersion, uint256 index)
        external
        view
        returns (Order memory order_);

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
    function getUsdnProtocol() external view returns (address);

    /**
     * @notice Initialize the contract with all the needed variables.
     * @param usdnProtocol The address of the USDN protocol
     */
    function initialize(IUsdnProtocol usdnProtocol) external;

    /// @notice Set the maximum approval for the USDN protocol to take assets from this contract.
    function approveAssetsForSpending(uint256 allowance) external;

    /**
     * @notice Add an order with the provided amount to the provided tick
     * and pull the amount of funds from the user to this contract.
     * @dev This function will always use the latest version of the provided tick.
     * @param tick The tick to add the order in.
     * @param amount The amount of asset the order contains.
     */
    function addOrderInTick(int24 tick, uint96 amount) external;

    /**
     * @notice Remove the order of the user from the provided tick and send back the funds to him.
     * @dev This function will always use the latest version of the provided tick.
     * @param tick The tick to remove the order from.
     */
    function removeOrderFromTick(int24 tick) external;
}
