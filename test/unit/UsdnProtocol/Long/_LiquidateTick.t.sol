// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { ProtocolAction, LiquidationEffects, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test the _liquidateTick internal function of the long layer
 * @custom:background Given an instantiated protocol with an order manager set
 */
contract TestUsdnProtocolLongLiquidateTick is UsdnProtocolBaseFixture {
    int24 _tick;
    uint256 _tickVersion;
    bytes32 _tickHash;
    uint128 _liqPrice;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableOrderManager = true;
        super._setUp(params);

        wstETH.mintAndApprove(address(this), 1 ether, address(orderManager), type(uint256).max);

        // Create a long position to liquidate
        uint128 price = 2000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        _liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);
        (_tick, _tickVersion,) =
            setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, _liqPrice, price);

        _tickHash = protocol.tickHash(_tick, _tickVersion);
    }

    function test_liquidateTickWithOrderManagerNotSet() public {
        // Unset the order manager
        vm.prank(ADMIN);
        protocol.setOrderManager(IOrderManager(address(0)));

        TickData memory tickData = protocol.getTickData(_tick);
        int256 tickValue = protocol.i_tickValue(_liqPrice, _tick, tickData);
        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(_tick);
        uint256 bitmapLastSetBefore = protocol.findLastSetInTickBitmap(_tick);

        vm.expectEmit();
        emit LiquidatedTick(_tick, _tickVersion, _liqPrice, liqPriceAfterFundings, tickValue);
        vm.recordLogs();
        LiquidationEffects memory effects = protocol.i_liquidateTick(_tick, _tickHash, tickData, _liqPrice);
        uint256 logsAmount = vm.getRecordedLogs().length;

        assertEq(logsAmount, 1, "Only the LiquidatedTick event should have been emitted");
        assertEq(effects.liquidatedPositions, 1, "One position should have been liquidated");
        assertEq(effects.remainingCollateral, tickValue, "The collateral remaining should equal the tick value");
        assertEq(effects.amountAddedToLong, 0, "No amount should have been added to long as no orders was processed");
        assertLt(
            protocol.findLastSetInTickBitmap(_tick),
            bitmapLastSetBefore,
            "The last set should be lower than before the liquidation"
        );
    }

    function test_liquidateTickWithNoOrders() public {
        TickData memory tickData = protocol.getTickData(_tick);
        int256 tickValue = protocol.i_tickValue(_liqPrice, _tick, tickData);

        vm.expectEmit(true, true, false, false);
        emit LiquidatedTick(_tick, _tickVersion, 0, 0, 0);
        vm.recordLogs();
        LiquidationEffects memory effects = protocol.i_liquidateTick(_tick, _tickHash, tickData, _liqPrice);
        uint256 logsAmount = vm.getRecordedLogs().length;

        assertEq(logsAmount, 1, "Only the LiquidatedTick event should have been emitted");
        assertEq(effects.remainingCollateral, tickValue, "The collateral remaining should equal the tick value");
        assertEq(effects.amountAddedToLong, 0, "No amount should have been added to long as no orders was processed");
    }

    function test_liquidateTickWithOrders() public {
        // Create an order in the tick to liquidate
        uint128 orderAmount = 1 ether;
        orderManager.depositAssetsInTick(_tick, orderAmount);

        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(_tick);

        // Calculate the collateral this position gives on liquidation
        TickData memory tickData = protocol.getTickData(_tick);
        int256 tickValue = protocol.i_tickValue(_liqPrice, _tick, tickData);
        uint128 ordersRewards = uint128(uint256(tickValue)) / 2;
        int256 expectedRemainingCollateral = tickValue - int256(uint256(ordersRewards));

        vm.expectEmit(true, false, false, false, address(protocol));
        emit OrderManagerPositionOpened(address(orderManager), 0, 0, 0, 0, 0);
        vm.expectEmit();
        emit LiquidatedTick(_tick, _tickVersion, _liqPrice, liqPriceAfterFundings, expectedRemainingCollateral);
        LiquidationEffects memory effects = protocol.i_liquidateTick(_tick, _tickHash, tickData, _liqPrice);

        assertEq(effects.liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(
            effects.remainingCollateral,
            expectedRemainingCollateral,
            "Collateral remaining should be equal to the expected value"
        );
        assertEq(effects.amountAddedToLong, orderAmount, "The amount in orders should have been added to the long side");
    }
}
