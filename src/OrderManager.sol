// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @title OrderManager contract
 * @notice This contract stores and manage orders that should serve to open a long position when a liquidation happen in
 * the same tick in the USDN protocol.
 */
contract OrderManager is Ownable, IOrderManager, InitializableReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    /// @notice The divisor for the ratio of assets used in _ordersDataInTick
    uint128 constant RATIO_OF_ASSETS_USED_DIVISOR = 1e32;

    /// @notice The USDN protocol
    IUsdnProtocol private _usdnProtocol;

    /// @notice The index of the order of a user in an order array
    mapping(address => mapping(bytes32 => uint256)) private _userOrderIndexInTick;

    /// @notice The orders for a tick hash
    mapping(bytes32 => Order[]) private _ordersInTick;

    /// @notice The accumulated data of all the orders for a tick hash
    mapping(bytes32 => OrdersDataInTick) private _ordersDataInTick;

    constructor() Ownable(msg.sender) { }

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

    /// @inheritdoc IOrderManager
    function getUsdnProtocol() external view returns (address) {
        return address(_usdnProtocol);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function initialize(IUsdnProtocol usdnProtocol) external onlyOwner initializer {
        _usdnProtocol = usdnProtocol;

        // Set allowance to allow the USDN protocol to pull assets from this contract
        usdnProtocol.getAsset().forceApprove(address(usdnProtocol), type(uint256).max);
    }

    /// @inheritdoc IOrderManager
    function approveAssetsForSpending(uint256 allowance) external onlyOwner {
        IUsdnProtocol usdnProtocol = _usdnProtocol;

        usdnProtocol.getAsset().safeIncreaseAllowance(address(usdnProtocol), allowance);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Order Management                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function addOrderInTick(int24 tick, uint96 amount) external initializedAndNonReentrant {
        IUsdnProtocol usdnProtocol = _usdnProtocol;

        // Check if the provided tick is valid and inside limits
        if (tick < TickMath.MIN_TICK || tick > TickMath.MAX_TICK) revert OrderManagerInvalidTick(tick);
        if (tick % usdnProtocol.getTickSpacing() != 0) revert OrderManagerInvalidTick(tick);

        uint256 tickVersion = usdnProtocol.getTickVersion(tick);
        bytes32 tickHash = usdnProtocol.tickHash(tick, tickVersion);
        uint256 orderIndex = _ordersInTick[tickHash].length;

        // If the array is not empty, check if the user already has an order in this tick
        if (orderIndex > 0 && _ordersInTick[tickHash][_userOrderIndexInTick[msg.sender][tickHash]].user == msg.sender) {
            revert OrderManagerUserAlreadyInTick(msg.sender, tick, tickVersion);
        }

        // Save the order's data
        _ordersDataInTick[tickHash].amountOfAssets += amount;
        _ordersInTick[tickHash].push(Order({ amountOfAssets: amount, user: msg.sender }));

        // Transfer the user assets to this contract
        usdnProtocol.getAsset().safeTransferFrom(msg.sender, address(this), amount);

        emit OrderCreated(msg.sender, amount, tick, tickVersion, orderIndex);
    }

    /// @inheritdoc IOrderManager
    function removeOrderFromTick(int24 tick) external initializedAndNonReentrant {
        IUsdnProtocol usdnProtocol = _usdnProtocol;
        uint256 tickVersion = usdnProtocol.getTickVersion(tick);
        bytes32 tickHash = usdnProtocol.tickHash(tick, tickVersion);
        uint256 ordersCountInTick = _ordersInTick[tickHash].length;

        // Check that the order array is not empty
        if (ordersCountInTick == 0) {
            revert OrderManagerEmptyTick(tick);
        }

        uint256 userOrderIndex = _userOrderIndexInTick[msg.sender][tickHash];
        Order memory userOrder = _ordersInTick[tickHash][userOrderIndex];

        // By default, userOrderIndex will be 0
        // So check that the order at that index matches the current user
        if (userOrder.user != msg.sender) {
            revert OrderManagerNoOrderForUserInTick(tick, msg.sender);
        }

        // If there are multiple orders in the tick
        if (ordersCountInTick > 1) {
            // Replace the user order with the last order in the array
            _ordersInTick[tickHash][userOrderIndex] = _ordersInTick[tickHash][ordersCountInTick - 1];
        }

        // Remove the last order (which should either be a duplicate, or the order to remove) from the array
        _ordersInTick[tickHash].pop();
        // And clean the storage from the removed position's data
        delete _userOrderIndexInTick[msg.sender][tickHash];
        _ordersDataInTick[tickHash].amountOfAssets -= userOrder.amountOfAssets;

        // Transfer the assets back to the user
        usdnProtocol.getAsset().safeTransfer(msg.sender, userOrder.amountOfAssets);

        emit OrderRemoved(msg.sender, tick, tickVersion, userOrderIndex);
    }
}
