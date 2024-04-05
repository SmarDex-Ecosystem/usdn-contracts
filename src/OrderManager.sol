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
 * @notice This contract stores and manages orders that should serve to open a long position when a liquidation happens
 * in the same tick in the USDN protocol.
 */
contract OrderManager is Ownable, IOrderManager {
    using SafeERC20 for IERC20Metadata;

    /// @inheritdoc IOrderManager
    int24 public constant PENDING_ORDERS_TICK = type(int24).min;

    /// @notice The USDN protocol
    IUsdnProtocol internal immutable _usdnProtocol;

    /// @notice The asset used in the USDN protocol
    IERC20Metadata internal immutable _asset;

    /// @notice The amount of assets a user has in a tick
    mapping(bytes32 => mapping(address => uint256)) internal _userAmountInTick;

    /// @notice The accumulated data of all the orders for a tick hash
    mapping(bytes32 => OrdersDataInTick) internal _ordersDataInTick;

    /// @notice The leverage of the long position created from orders in a tick
    uint256 internal _ordersLeverage;

    /**
     * @notice Initialize the contract with all the needed variables.
     * @param usdnProtocol The address of the USDN protocol
     */
    constructor(IUsdnProtocol usdnProtocol) Ownable(msg.sender) {
        _usdnProtocol = usdnProtocol;
        _asset = usdnProtocol.getAsset();

        // Set allowance to allow the USDN protocol to pull assets from this contract
        _asset.forceApprove(address(usdnProtocol), type(uint256).max);

        // Set the default leverage
        _ordersLeverage = 2 * 10 ** usdnProtocol.LEVERAGE_DECIMALS();
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Getters                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function getUserAmountInTick(int24 tick, uint256 tickVersion, address user) external view returns (uint256) {
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

    /// @inheritdoc IOrderManager
    function getOrdersLeverage() external view returns (uint256) {
        return _ordersLeverage;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function setOrdersLeverage(uint256 newLeverage) external onlyOwner {
        if (newLeverage < _usdnProtocol.getMinLeverage() || newLeverage > _usdnProtocol.getMaxLeverage()) {
            revert OrderManagerInvalidLeverage();
        }

        _ordersLeverage = newLeverage;

        emit OrdersLeverageUpdated(newLeverage);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Order Management                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOrderManager
    function depositAssetsInTick(int24 tick, uint232 amount) external {
        IUsdnProtocol usdnProtocol = _usdnProtocol;

        // Check if the provided tick is valid and inside limits
        if (tick < TickMath.MIN_TICK || tick > TickMath.MAX_TICK || tick % usdnProtocol.getTickSpacing() != 0) {
            revert OrderManagerInvalidTick(tick);
        }

        // Get the tick hash the order will be in
        uint256 tickVersion = usdnProtocol.getTickVersion(tick);
        bytes32 tickHash = usdnProtocol.tickHash(tick, tickVersion);

        // Save the order's data
        uint256 newUserAmount = _userAmountInTick[tickHash][msg.sender] + amount;
        OrdersDataInTick storage ordersData = _ordersDataInTick[tickHash];
        ordersData.amountOfAssets += amount;
        ordersData.longPositionTick = PENDING_ORDERS_TICK;
        _userAmountInTick[tickHash][msg.sender] = newUserAmount;

        // Transfer the user assets to this contract
        _asset.safeTransferFrom(msg.sender, address(this), amount);

        emit UserDepositedAssetsInTick(msg.sender, newUserAmount, tick, tickVersion);
    }

    /// @inheritdoc IOrderManager
    function withdrawAssetsFromTick(int24 tick, uint256 tickVersion, uint232 amountToWithdraw) external {
        IUsdnProtocol usdnProtocol = _usdnProtocol;
        bytes32 tickHash = usdnProtocol.tickHash(tick, tickVersion);
        uint256 userAmount = _userAmountInTick[tickHash][msg.sender];

        OrdersDataInTick memory ordersData = _ordersDataInTick[tickHash];
        if (ordersData.longPositionTick != PENDING_ORDERS_TICK) {
            revert OrderManagerOrderNotPending(tick, tickVersion);
        }

        // Check that the current user has assets in this tick
        if (userAmount < amountToWithdraw) {
            revert OrderManagerInsufficientFunds(tick, msg.sender, userAmount, amountToWithdraw);
        }

        // Remove the amount from the storage
        uint256 newUserAmount = userAmount - amountToWithdraw;
        _userAmountInTick[tickHash][msg.sender] = newUserAmount;
        _ordersDataInTick[tickHash].amountOfAssets -= amountToWithdraw;

        // Transfer the assets back to the user
        _asset.safeTransfer(msg.sender, amountToWithdraw);

        emit UserWithdrewAssetsFromTick(msg.sender, newUserAmount, tick, tickVersion);
    }

    /// @inheritdoc IOrderManager
    function fulfillOrdersInTick(uint128 currentPrice, bytes32 liquidatedTickHash)
        external
        returns (int24 longPositionTick_, uint256 amount_)
    {
        // This function can only be called by the USDN protocol
        if (msg.sender != address(_usdnProtocol)) {
            revert OrderManagerCallerIsNotUSDNProtocol(msg.sender);
        }

        OrdersDataInTick storage ordersData = _ordersDataInTick[liquidatedTickHash];
        amount_ = ordersData.amountOfAssets;
        if (amount_ == 0) {
            return (PENDING_ORDERS_TICK, 0);
        }

        // Check if allowance is sufficient, if not, set back to max
        uint256 remainingAllowance = _asset.allowance(address(this), address(_usdnProtocol));
        if (remainingAllowance < amount_) {
            _asset.safeIncreaseAllowance(address(_usdnProtocol), type(uint256).max - remainingAllowance);
        }

        // Calculate the liquidation price relative to the leverage
        // _ordersLeverage limits are below type(uint128).max, so cast is safe here
        uint256 liquidationPrice =
            currentPrice - ((10 ** _usdnProtocol.LEVERAGE_DECIMALS() * currentPrice) / _ordersLeverage);

        // Save the position tick in the orders data
        // TODO import safecast library? *go cry in a corner*
        longPositionTick_ = _usdnProtocol.getEffectiveTickForPrice(uint128(liquidationPrice));

        // Update the orders data with the long position information
        ordersData.longPositionTick = longPositionTick_;
        ordersData.longPositionTickVersion = _usdnProtocol.getTickVersion(longPositionTick_);
        ordersData.longPositionIndex = _usdnProtocol.getPositionsInTick(longPositionTick_);
    }
}
