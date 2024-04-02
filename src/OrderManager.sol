// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { TickMath } from "src/libraries/TickMath.sol";

/**
 * @title OrderManager contract
 * @notice This contract stores and manage orders that should serve to open a long position when a liquidation happen in
 * the same tick in the USDN protocol.
 */
contract OrderManager is Ownable, IOrderManager {
    using SafeERC20 for IERC20Metadata;

    int24 public constant PENDING_ORDERS_TICK = type(int24).min;

    /// @notice The USDN protocol
    IUsdnProtocol internal immutable _usdnProtocol;

    /// @notice The asset used in the USDN protocol
    IERC20Metadata internal immutable _asset;

    /// @notice The amount of assets a user has in a tick
    mapping(bytes32 => mapping(address => uint232)) _userAmountInTick;

    /// @notice The accumulated data of all the orders for a tick hash
    mapping(bytes32 => OrdersDataInTick) internal _ordersDataInTick;

    /**
     * @notice Initialize the contract with all the needed variables.
     * @param usdnProtocol The address of the USDN protocol
     */
    constructor(IUsdnProtocol usdnProtocol) Ownable(msg.sender) {
        _usdnProtocol = usdnProtocol;
        _asset = usdnProtocol.getAsset();

        // Set allowance to allow the USDN protocol to pull assets from this contract
        _asset.forceApprove(address(usdnProtocol), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Getters                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function getUserAmountInTick(int24 tick, uint256 tickVersion, address user) external view returns (uint232) {
        bytes32 tickHash = _usdnProtocol.tickHash(tick, tickVersion);

        return _userAmountInTick[tickHash][user];
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
    function getUsdnProtocol() external view returns (IUsdnProtocol) {
        return _usdnProtocol;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function approveAssetsForSpending(uint256 allowance) external onlyOwner {
        IUsdnProtocol usdnProtocol = _usdnProtocol;

        _asset.safeIncreaseAllowance(address(usdnProtocol), allowance);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Order Management                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function addOrderInTick(int24 tick, uint96 amount) external {
        IUsdnProtocol usdnProtocol = _usdnProtocol;

        // Check if the provided tick is valid and inside limits
        if (tick < TickMath.MIN_TICK || tick > TickMath.MAX_TICK || tick % usdnProtocol.getTickSpacing() != 0) {
            revert OrderManagerInvalidTick(tick);
        }

        uint256 tickVersion = usdnProtocol.getTickVersion(tick);
        bytes32 tickHash = usdnProtocol.tickHash(tick, tickVersion);

        // If the array is not empty, check if the user already has an order in this tick
        if (_userAmountInTick[tickHash][msg.sender] > 0) {
            revert OrderManagerUserAlreadyInTick(msg.sender, tick, tickVersion);
        }

        // Save the order's data
        _ordersDataInTick[tickHash].amountOfAssets += amount;
        _ordersDataInTick[tickHash].longPositionTick = PENDING_ORDERS_TICK;

        _userAmountInTick[tickHash][msg.sender] = amount;

        // Transfer the user assets to this contract
        _asset.safeTransferFrom(msg.sender, address(this), amount);

        emit OrderCreated(msg.sender, amount, tick, tickVersion);
    }

    /// @inheritdoc IOrderManager
    function removeOrderFromTick(int24 tick) external {
        IUsdnProtocol usdnProtocol = _usdnProtocol;
        uint256 tickVersion = usdnProtocol.getTickVersion(tick);
        bytes32 tickHash = usdnProtocol.tickHash(tick, tickVersion);
        uint232 userAmount = _userAmountInTick[tickHash][msg.sender];

        // Check that the current user has assets in this tick
        if (userAmount == 0) {
            revert OrderManagerNoOrderForUserInTick(tick, msg.sender);
        }

        // And clean the storage from the removed position's data
        delete _userAmountInTick[tickHash][msg.sender];
        _ordersDataInTick[tickHash].amountOfAssets -= userAmount;

        // Transfer the assets back to the user
        _asset.safeTransfer(msg.sender, userAmount);

        emit OrderRemoved(msg.sender, tick, tickVersion);
    }
}
