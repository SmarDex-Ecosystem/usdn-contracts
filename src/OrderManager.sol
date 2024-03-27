// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { TickMath } from "src/libraries/TickMath.sol";

contract OrderManager is Ownable, IOrderManager {
    using SafeERC20 for IERC20Metadata;

    /// @notice The divisor for the ratio of assets used in _ordersDataInTick
    uint128 constant RATIO_OF_ASSETS_USED_DIVISOR = 1e32;

    /// @notice Is the contract initialized
    bool private _isInitialized;

    /// @notice The USDN protocol
    IUsdnProtocol private _usdnProtocol;

    /// @notice The index of the order of a user in an order array
    mapping(address => mapping(bytes32 => uint256)) private _userOrderIndexInTick;

    /// @notice The orders for a tick hash
    mapping(bytes32 => Order[]) private _ordersInTick;

    /// @notice The accumulated data of all the orders for a tick hash
    mapping(bytes32 => OrdersDataInTick) private _ordersDataInTick;

    constructor() Ownable(msg.sender) { }

    /// @dev Prevent some functions to be used if the initialize function hasn't been called yet.
    modifier initialized() {
        if (!_isInitialized) revert OrderManagerNotInitialized();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Getters                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function getOrderInTickAtIndex(int24 tick, uint256 tickVersion, uint256 index)
        external
        view
        returns (Order memory order_)
    {
        bytes32 tickHash = _usdnProtocol.tickHash(tick, tickVersion);

        order_ = _ordersInTick[tickHash][index];
    }

    /// @inheritdoc IOrderManager
    function getOrdersDataInTick(int24 tick, uint256 tickVersion)
        external
        view
        returns (OrdersDataInTick memory ordersData_)
    {
        bytes32 tickHash = _usdnProtocol.tickHash(tick, tickVersion);

        ordersData_ = _ordersDataInTick[tickHash];
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initialize the contract with all the needed variables.
     * @param usdnProtocol The address of the USDN protocol
     */
    function initialize(IUsdnProtocol usdnProtocol) external onlyOwner {
        _usdnProtocol = usdnProtocol;
        // Unsafe ? Transfer assets on position creation instead ?
        // Depends on how the position is created on the protocol side.
        _usdnProtocol.getAsset().approve(address(usdnProtocol), type(uint256).max);
        _isInitialized = true;
    }

    /// @notice Set the maximum approval for the USDN protocol to take assets from this contract.
    function approveAssetsForSpending() external initialized onlyOwner {
        _usdnProtocol.getAsset().approve(address(_usdnProtocol), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Order Management                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function addOrderInTick(int24 tick, uint96 amount) external initialized {
        // Check if the provided tick is valid and inside limits
        if (tick < TickMath.MIN_TICK || tick > TickMath.MAX_TICK) revert OrderManagerInvalidTick(tick);
        if (tick % _usdnProtocol.getTickSpacing() != 0) revert OrderManagerInvalidTick(tick);

        uint256 tickVersion = _usdnProtocol.getTickVersion(tick);
        bytes32 tickHash = _usdnProtocol.tickHash(tick, tickVersion);
        uint256 orderIndex = _ordersInTick[tickHash].length;

        // If the array is not empty, check if the user already has an order in this tick
        if (orderIndex > 0 && _ordersInTick[tickHash][_userOrderIndexInTick[msg.sender][tickHash]].user == msg.sender) {
            revert OrderManagerUserAlreadyInTick(msg.sender, tick, tickVersion);
        }

        // Save the order's data
        _ordersDataInTick[tickHash].amountOfAssets += amount;
        _ordersInTick[tickHash].push(Order({ amountOfAssets: amount, user: msg.sender }));

        // Transfer the user assets to this contract
        _usdnProtocol.getAsset().safeTransferFrom(msg.sender, address(this), amount);

        emit OrderCreated(msg.sender, amount, tick, tickVersion, orderIndex);
    }

    /// @inheritdoc IOrderManager
    function removeOrderFromTick(int24 tick) external initialized {
        uint256 tickVersion = _usdnProtocol.getTickVersion(tick);
        bytes32 tickHash = _usdnProtocol.tickHash(tick, tickVersion);

        // Cache orders for the tick in memory
        Order[] memory orders = _ordersInTick[tickHash];
        uint256 ordersLength = orders.length;

        // Check that the order array is not empty
        if (ordersLength == 0) {
            revert OrderManagerEmptyTick(tick);
        }

        uint256 userOrderIndex = _userOrderIndexInTick[msg.sender][tickHash];
        Order memory userOrder = orders[userOrderIndex];

        // By default, userOrderIndex will be 0
        // So check that the order at that index matches the current user
        if (userOrder.user != msg.sender) {
            revert OrderManagerNoOrderForUserInTick(tick, msg.sender);
        }

        // If there are multiple orders in the tick
        if (orders.length > 1) {
            // Replace the user order with the last order in the array
            _ordersInTick[tickHash][userOrderIndex] = orders[orders.length - 1];
        }

        // Remove the last order (which should either be a duplicate, or the order to remove) from the array
        _ordersInTick[tickHash].pop();
        // And clean the storage from the removed position's data
        delete _userOrderIndexInTick[msg.sender][tickHash];
        _ordersDataInTick[tickHash].amountOfAssets -= userOrder.amountOfAssets;

        // Transfer the assets back to the user
        _usdnProtocol.getAsset().safeTransfer(msg.sender, userOrder.amountOfAssets);

        emit OrderRemoved(msg.sender, tick, tickVersion, userOrderIndex);
    }
}
