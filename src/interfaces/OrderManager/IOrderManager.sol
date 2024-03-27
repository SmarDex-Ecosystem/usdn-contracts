// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";

interface IOrderManager is IOrderManagerErrors, IOrderManagerEvents {
    /**
     * @notice The accumulated data of all the orders in a tick.
     * @param amountOfAssets The amount of assets in the tick.
     * @param usedAmountOfAssetsRatio The ratio of assets used in the tick (0 if tick is still available).
     */
    struct OrdersDataInTick {
        uint96 amountOfAssets;
        uint128 usedAmountOfAssetsRatio;
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
