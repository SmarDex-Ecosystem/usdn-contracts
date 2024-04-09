// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { Position, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";

/**
 * @custom:feature The _saveOrderManagerPositionInTick internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol an initialized protocol with default params
 * @custom:and a validated long position of 1 ether with 5x leverage
 */
contract TestUsdnProtocolLongSaveOrderManagerPositionInTick is UsdnProtocolBaseFixture {
    uint128 private _liqPrice;
    int24 private _tick;
    uint256 private _tickVersion;
    bytes32 private _tickHash;
    uint128 private _tickTotalExpo;
    uint128 private _positionAmount = 1 ether;
    uint128 private _orderAmount = 1 ether;

    function setUp() external {
        params = DEFAULT_PARAMS;
        params.flags.enableOrderManager = true;
        _setUp(params);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        wstETH.approve(address(orderManager), type(uint256).max);

        uint128 liquidationPrice = params.initialPrice - (params.initialPrice / 5);
        (_tick, _tickVersion,) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, _positionAmount, liquidationPrice, params.initialPrice
        );

        _liqPrice = protocol.getEffectivePriceForTick(_tick);
        _tickHash = protocol.tickHash(_tick, _tickVersion);
        _tickTotalExpo = uint128(protocol.getTotalExpoByTick(_tick));

        orderManager.depositAssetsInTick(_tick, _orderAmount);
    }

    /**
     * @custom:scenario A tick with orders is liquidated
     * @custom:given The USDN protocol with an order on the tick to liquidate
     * @custom:when A tick with orders is liquidated
     * @custom:then A position belonging to the order manager is created
     */
    function test_saveOrderManagerPositionInTick() public {
        uint256 longPositionsCountBefore = protocol.getTotalLongPositions();
        uint256 protocolAssetsBefore = wstETH.balanceOf(address(protocol));
        uint256 orderManagerAssetsBefore = wstETH.balanceOf(address(orderManager));
        uint128 ordersLeverage = uint128(orderManager.getOrdersLeverage());
        uint256 balanceLongBefore = protocol.getBalanceLong();
        int24 expectedLongTick =
            protocol.getEffectiveTickForPrice(protocol.i_getLiquidationPrice(_liqPrice, ordersLeverage));
        uint256 expectedLongTickVersion = 0;
        uint256 expectedLongIndex = 0;

        vm.expectEmit();
        emit OrderManagerPositionOpened(
            address(orderManager),
            uint40(block.timestamp),
            ordersLeverage,
            _orderAmount,
            _liqPrice,
            expectedLongTick,
            expectedLongTickVersion,
            expectedLongIndex
        );
        int256 tempLongBalance =
            protocol.i_saveOrderManagerPositionInTick(_liqPrice, _tickHash, _tickTotalExpo, int256(balanceLongBefore));

        /* ------------------------------ Global checks ----------------------------- */
        assertEq(longPositionsCountBefore + 1, protocol.getTotalLongPositions(), "1 position should have been created");
        assertEq(
            protocolAssetsBefore + _orderAmount,
            wstETH.balanceOf(address(protocol)),
            "Assets from the orders in the tick should have been transferred to the protocol"
        );
        assertEq(
            orderManagerAssetsBefore - _orderAmount,
            wstETH.balanceOf(address(orderManager)),
            "Assets from the orders in the tick should have been transferred out of the order manager"
        );
        assertEq(
            balanceLongBefore + _orderAmount,
            uint256(tempLongBalance),
            "The returned long balance should be the balance long before + the amount in the position"
        );

        /* ----------------------------- Position checks ---------------------------- */
        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(_tick, _tickVersion);
        Position memory pos = protocol.getLongPosition(
            ordersData.longPositionTick, ordersData.longPositionTickVersion, ordersData.longPositionIndex
        );

        uint128 posLiqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            expectedLongTick - protocol.getTickSpacing() * int24(protocol.getLiquidationPenalty())
        );
        uint256 ordersTotalExpo =
            protocol.i_calculatePositionTotalExpo(_orderAmount, _liqPrice, posLiqPriceWithoutPenalty);
        assertEq(pos.user, address(orderManager), "The position should belong to the order manager");
        assertEq(pos.timestamp, block.timestamp, "The timestamp should be now");
        assertEq(pos.totalExpo, ordersTotalExpo, "The total expo should be equal to the total expo of the orders");
        assertEq(pos.amount, _orderAmount, "The amount should be equal to the amount of assets in the orders");
    }

    /**
     * @custom:scenario A tick with orders with more assets than necessary is liquidated
     * @custom:given The USDN protocol with an order with more assets than the tick to liquidate
     * @custom:when A tick with orders is liquidated
     * @custom:then A position belonging to the order manager is created
     * @custom:and the position only has the amount necessary to match the total expo liquidated
     */
    function test_saveOrderManagerPositionInTickWithMaxTotalExpoReached() public {
        uint128 ordersLeverage = uint128(orderManager.getOrdersLeverage());
        int24 expectedLongTick =
            protocol.getEffectiveTickForPrice(protocol.i_getLiquidationPrice(_liqPrice, ordersLeverage));
        uint256 expectedLongTickVersion = 0;
        uint256 expectedLongIndex = 0;
        uint128 posLiqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            expectedLongTick - protocol.getTickSpacing() * int24(protocol.getLiquidationPenalty())
        );

        // Deposit more assets than necessary
        uint128 maxAmount = protocol.i_calcPositionAmount(_tickTotalExpo, _liqPrice, posLiqPriceWithoutPenalty);
        orderManager.depositAssetsInTick(_tick, maxAmount);
        _orderAmount += maxAmount;

        uint256 longPositionsCountBefore = protocol.getTotalLongPositions();
        uint256 protocolAssetsBefore = wstETH.balanceOf(address(protocol));
        uint256 orderManagerAssetsBefore = wstETH.balanceOf(address(orderManager));
        uint256 balanceLongBefore = protocol.getBalanceLong();

        vm.expectEmit();
        emit OrderManagerPositionOpened(
            address(orderManager),
            uint40(block.timestamp),
            ordersLeverage,
            maxAmount,
            _liqPrice,
            expectedLongTick,
            expectedLongTickVersion,
            expectedLongIndex
        );
        int256 tempLongBalance =
            protocol.i_saveOrderManagerPositionInTick(_liqPrice, _tickHash, _tickTotalExpo, int256(balanceLongBefore));

        /* ------------------------------ Global checks ----------------------------- */
        assertEq(longPositionsCountBefore + 1, protocol.getTotalLongPositions(), "1 position should have been created");
        assertEq(
            protocolAssetsBefore + maxAmount,
            wstETH.balanceOf(address(protocol)),
            "The max amount available to open a position should have been transferred to the protocol"
        );
        assertEq(
            orderManagerAssetsBefore - maxAmount,
            wstETH.balanceOf(address(orderManager)),
            "The max amount available to open a position should have been transferred out of the order manager"
        );
        assertEq(
            balanceLongBefore + maxAmount,
            uint256(tempLongBalance),
            "The returned long balance should be the balance long before + the amount in the position"
        );

        /* ----------------------------- Position checks ---------------------------- */
        IOrderManager.OrdersDataInTick memory ordersData = orderManager.getOrdersDataInTick(_tick, _tickVersion);
        Position memory pos = protocol.getLongPosition(
            ordersData.longPositionTick, ordersData.longPositionTickVersion, ordersData.longPositionIndex
        );

        assertEq(pos.user, address(orderManager), "The position should belong to the order manager");
        assertEq(pos.timestamp, block.timestamp, "The timestamp should be now");
        assertEq(pos.totalExpo, _tickTotalExpo, "The total expo should be equal to the total expo of the orders");
        assertEq(
            pos.amount, maxAmount, "The amount should be equal to the max amount of assets for the tick total expo"
        );
    }

    /**
     * @custom:scenario A tick with orders is liquidated but the order manager contract is not set
     * @custom:given The USDN protocol with no order manager set
     * @custom:when A tick with orders is liquidated
     * @custom:then No positions are created and assets are not transferred
     */
    function test_saveOrderManagerPositionInTickDoesNothingIfOrderManagerNotSet() public {
        vm.prank(ADMIN);
        protocol.setOrderManager(IOrderManager(address(0)));

        uint256 longPositionsCountBefore = protocol.getTotalLongPositions();
        uint256 protocolAssetsBefore = wstETH.balanceOf(address(protocol));

        vm.recordLogs();
        int256 tempLongBalance = protocol.i_saveOrderManagerPositionInTick(
            _liqPrice, _tickHash, _tickTotalExpo, int256(protocol.getBalanceLong())
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "No logs should have been emitted");

        assertEq(
            longPositionsCountBefore,
            protocol.getTotalLongPositions(),
            "There should have been no additional position created"
        );

        assertEq(
            protocolAssetsBefore,
            wstETH.balanceOf(address(protocol)),
            "No assets should have been transferred to the protocol"
        );

        assertEq(
            tempLongBalance,
            int256(protocol.getBalanceLong()),
            "The protocol long balance should be equal to the returned long balance"
        );
    }

    /**
     * @custom:scenario A tick is liquidated but no orders are on this tick
     * @custom:given The USDN protocol with no order manager set
     * @custom:when A tick with orders is liquidated
     * @custom:then No positions are created and assets are not transferred
     */
    function test_saveOrderManagerPositionInTickDoesNothingIfNoOrders() public {
        uint256 longPositionsCountBefore = protocol.getTotalLongPositions();
        uint256 protocolAssetsBefore = wstETH.balanceOf(address(protocol));

        bytes32 tickHash = protocol.tickHash(_tick - protocol.getTickSpacing(), 0);
        protocol.i_saveOrderManagerPositionInTick(
            _liqPrice, tickHash, _tickTotalExpo, int256(protocol.getBalanceLong())
        );

        assertEq(
            longPositionsCountBefore,
            protocol.getTotalLongPositions(),
            "There should have been no additional position created"
        );

        assertEq(
            protocolAssetsBefore,
            wstETH.balanceOf(address(protocol)),
            "No assets should have been transferred to the protocol"
        );
    }
}
