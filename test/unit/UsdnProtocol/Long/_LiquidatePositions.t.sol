// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { TickMath } from "../../../../src/libraries/TickMath.sol";

/// @custom:feature Test the _liquidatePositions internal function of the long layer
contract TestUsdnProtocolLongLiquidatePositions is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Make sure nothing happens if there are no ticks to liquidate above the provided price
     * @custom:given There are no positions with a liquidation price above current price
     * @custom:when User calls _liquidatePositions
     * @custom:then Nothing should happen
     * @custom:and 0s should be returned
     */
    function test_nothingHappensWhenThereIsNothingToLiquidate() public {
        vm.recordLogs();
        LiquidationsEffects memory liquidationsEffects = protocol.i_liquidatePositions(2000 ether, 1, 5 ether, 5 ether);
        uint256 logsAmount = vm.getRecordedLogs().length;

        assertEq(logsAmount, 0, "No event should have been emitted");
        assertEq(
            liquidationsEffects.liquidatedPositions, 0, "No position should have been liquidated at the given price"
        );
        assertEq(liquidationsEffects.liquidatedTicks.length, 0, "No tick should have been liquidated at this price");
        assertEq(liquidationsEffects.remainingCollateral, 0, "There should have been no changes to the collateral");
        assertEq(liquidationsEffects.newLongBalance, 5 ether, "There should have been no changes to the long balance");
        assertEq(liquidationsEffects.newVaultBalance, 5 ether, "There should have been no changes to the vault balance");
    }

    /**
     * @custom:scenario A position is underwater and can be liquidated
     * @custom:given A position has its liquidation price above current price
     * @custom:when User calls _liquidatePositions
     * @custom:then It should liquidate the position.
     */
    function test_canLiquidateAPosition() public {
        uint128 price = 2000 ether;
        uint128 desiredLiqPrice = price - 200 ether;

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        uint128 liqPrice = protocol.getEffectivePriceForTick(posId.tick);
        uint256 balanceLong = protocol.longAssetAvailableWithFunding(liqPrice, uint128(block.timestamp));
        uint256 balanceVault = protocol.vaultAssetAvailableWithFunding(liqPrice, uint128(block.timestamp));
        uint256 longTradingExpo = protocol.getTotalExpo() - balanceLong;
        uint128 effectiveTickPrice = protocol.getEffectivePriceForTick(
            posId.tick, liqPrice, longTradingExpo, protocol.getLiqMultiplierAccumulator()
        );

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.tickValue(posId.tick, liqPrice);

        vm.expectEmit();
        emit LiquidatedTick(posId.tick, 0, liqPrice, effectiveTickPrice, tickValue);

        vm.recordLogs();
        vm.expectEmit();
        emit HighestPopulatedTickUpdated(initialPosition.tick);
        LiquidationsEffects memory liquidationsEffects =
            protocol.i_liquidatePositions(uint256(liqPrice), 1, int256(balanceLong), int256(balanceVault));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 logsAmount = logs.length;
        uint256 liquidationLogsCount;

        // filter logs
        for (uint256 i = 0; i < logsAmount; i++) {
            bytes32 topic = logs[i].topics[0];
            if (topic == LiquidatedTick.selector) {
                liquidationLogsCount++;
            }
        }

        assertEq(liquidationLogsCount, 1, "Only one liquidation log should have been emitted");
        assertEq(liquidationsEffects.liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidationsEffects.liquidatedTicks.length, 1, "Only one tick should have been liquidated");
        assertEq(
            liquidationsEffects.remainingCollateral, tickValue, "Remaining collateral should be equal to tickValue"
        );
        assertEq(
            liquidationsEffects.newLongBalance,
            balanceLong - uint256(tickValue),
            "The long side should have paid tickValue to the vault side"
        );
        assertEq(
            int256(liquidationsEffects.newVaultBalance),
            int256(balanceVault) + tickValue,
            "The vault side should have received tickValue from the long side"
        );

        assertLt(
            protocol.getHighestPopulatedTick(),
            posId.tick,
            "The highest populated tick should be lower than the last liquidated tick"
        );
    }

    /**
     * @custom:scenario A position becomes underwater because of fundings and can be liquidated
     * @custom:given A position has its liquidation price above current price because of fundings
     * @custom:and the asset's price did not move
     * @custom:when User calls _liquidatePositions
     * @custom:then It should liquidate the position.
     */
    function test_canLiquidateAPositionWithFundings() public {
        vm.skip(true); // TODO: rewrite this test to use the public function, as now `i_applyPnlAndFunding` does not
        // mutate the balances and the test doesn't pass anymore. The fundings now only have effect through their effect
        // on the long balance.
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        super._setUp(params);

        uint128 price = 2000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Create a long position to liquidate
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: liqPrice,
                price: price
            })
        );

        skip(3 days);
        protocol.i_applyPnlAndFunding(price, uint128(block.timestamp));

        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(desiredLiqTick);
        assertGt(
            liqPriceAfterFundings, price, "The fundings did not push the liquidation price above the current price"
        );

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.tickValue(desiredLiqTick, price);
        // Sanity check
        // Make sure we do not end up in a bad debt situation because of fundings
        assertGt(tickValue, 1, "Waited too long before liquidation, lower the skipped time");

        vm.expectEmit();
        emit LiquidatedTick(desiredLiqTick, 0, price, liqPriceAfterFundings, tickValue);
        LiquidationsEffects memory liquidationsEffects = protocol.i_liquidatePositions(price, 1, 100 ether, 100 ether);

        assertEq(liquidationsEffects.liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidationsEffects.liquidatedTicks.length, 1, "Only one tick should have been liquidated");
        assertEq(
            liquidationsEffects.remainingCollateral, tickValue, "Collateral liquidated should be equal to tickValue"
        );
        assertEq(
            int256(liquidationsEffects.newLongBalance),
            100 ether - tickValue,
            "The long side should have paid tickValue to the vault side"
        );
        assertEq(
            int256(liquidationsEffects.newVaultBalance),
            100 ether + tickValue,
            "The long side should have paid tickValue to the vault side"
        );
    }

    /**
     * @custom:scenario The last position in the protocol is underwater and can be liquidated
     * @custom:given A position has its liquidation price above current price
     * @custom:when User calls _liquidatePositions with 2 iterations
     * @custom:then It should liquidate the position.
     */
    function test_canLiquidateTheLastPosition() public {
        int24 tick = protocol.getHighestPopulatedTick();
        uint128 liqPrice = protocol.getEffectivePriceForTick(tick);
        uint256 balanceLong = protocol.longAssetAvailableWithFunding(liqPrice, uint128(block.timestamp));
        uint256 balanceVault = protocol.vaultAssetAvailableWithFunding(liqPrice, uint128(block.timestamp));
        uint256 longTradingExpo = protocol.getTotalExpo() - balanceLong;
        uint128 effectiveTickPrice =
            protocol.getEffectivePriceForTick(tick, liqPrice, longTradingExpo, protocol.getLiqMultiplierAccumulator());

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.tickValue(tick, liqPrice);
        int24 minUsableTick = TickMath.minUsableTick(protocol.getTickSpacing());

        vm.expectEmit();
        emit LiquidatedTick(tick, 0, liqPrice, effectiveTickPrice, tickValue);
        vm.expectEmit();
        emit HighestPopulatedTickUpdated(minUsableTick);

        vm.recordLogs();
        // 2 Iterations to make sure we break the loop when there are no ticks to be found
        LiquidationsEffects memory liquidationsEffects =
            protocol.i_liquidatePositions(uint256(liqPrice), 2, int256(balanceLong), int256(balanceVault));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 logsAmount = logs.length;

        uint256 liquidationLogsCount;
        // filter logs
        for (uint256 i = 0; i < logsAmount; i++) {
            bytes32 topic = logs[i].topics[0];
            if (topic == LiquidatedTick.selector) {
                liquidationLogsCount++;
            }
        }

        assertEq(liquidationLogsCount, 1, "Only one log should have been emitted");
        assertEq(liquidationsEffects.liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(
            protocol.getHighestPopulatedTick(),
            minUsableTick,
            "The highest populated tick should be equal to the lowest usable tick"
        );
    }

    /**
     * @custom:scenario Even if the iteration parameter is above MAX_LIQUIDATION_ITERATION,
     * we will only iterate an amount of time equal to MAX_LIQUIDATION_ITERATION
     * @custom:given MAX_LIQUIDATION_ITERATION + 1 tick can be liquidated
     * @custom:when User calls _liquidatePositions with an iteration parameter set at MAX_LIQUIDATION_ITERATION + 1
     * @custom:then It should liquidate MAX_LIQUIDATION_ITERATION ticks.
     * @custom:and There should be 1 tick left to liquidate.
     */
    function test_liquidationIterationsAreCapped() public {
        uint128 price = 2000 ether;
        uint16 maxIterations = protocol.MAX_LIQUIDATION_ITERATION();
        uint128 desiredLiqPrice = price - 200 ether;

        // Iterate once more than the maximum of liquidations allowed
        int24[] memory ticksToLiquidate = new int24[](maxIterations + 1);
        for (uint16 i = 0; i < maxIterations + 1; ++i) {
            // Calculate the right tick for the iteration
            desiredLiqPrice *= 98;
            desiredLiqPrice /= 100;

            // Create a long position to liquidate
            PositionId memory posId = setUpUserPositionInLong(
                OpenParams({
                    user: address(this),
                    untilAction: ProtocolAction.ValidateOpenPosition,
                    positionSize: 1 ether,
                    desiredLiqPrice: desiredLiqPrice,
                    price: price
                })
            );

            // Save the tick for future checks
            ticksToLiquidate[i] = posId.tick;
        }

        // Set a price below all others
        uint128 liqPrice = desiredLiqPrice - 100 ether;
        int256 balanceLong = protocol.i_longAssetAvailable(liqPrice);
        int256 balanceVault = protocol.i_vaultAssetAvailable(liqPrice);

        // Expect MAX_LIQUIDATION_ITERATION events
        for (uint256 i = 0; i < maxIterations; ++i) {
            vm.expectEmit(true, true, false, false);
            emit LiquidatedTick(ticksToLiquidate[i], 0, 0, 0, 0);
        }

        vm.expectEmit();
        emit HighestPopulatedTickUpdated(ticksToLiquidate[ticksToLiquidate.length - 1]);
        // Make sure no more than MAX_LIQUIDATION_ITERATION events have been emitted
        vm.recordLogs();
        LiquidationsEffects memory liquidationsEffects =
            protocol.i_liquidatePositions(uint256(liqPrice), maxIterations + 1, balanceLong, balanceVault);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 logsAmount = logs.length;

        uint256 liquidationLogsCount;
        // filter logs
        for (uint256 i = 0; i < logsAmount; i++) {
            bytes32 topic = logs[i].topics[0];
            if (topic == LiquidatedTick.selector) {
                liquidationLogsCount++;
            }
        }

        assertEq(
            liquidationLogsCount,
            maxIterations,
            "An amount of events equal to MAX_LIQUIDATION_ITERATION should have been emitted"
        );

        assertEq(
            liquidationsEffects.liquidatedTicks.length,
            maxIterations,
            "The amount of ticks liquidated should be equal to MAX_LIQUIDATION_ITERATION"
        );

        assertEq(
            protocol.getHighestPopulatedTick(),
            ticksToLiquidate[ticksToLiquidate.length - 1],
            "Max initialized tick should be the last tick left to liquidate"
        );
    }

    /**
     * @custom:scenario A position can be liquidated but there is not enough balance in the longs to cover
     * the debt to the vault
     * @custom:given A position with a value of X that can be liquidated
     * @custom:and A long balance at X - 1
     * @custom:when User calls _liquidatePositions
     * @custom:then It should liquidate the position
     * @custom:and The long balance should be at 0
     * @custom:and The vault should have absorbed the long side's debt
     */
    function test_canLiquidateEvenWithBadDebtInLongs() public {
        vm.skip(true); // this case is not possible anymore with the new liquidation multiplier accumulator
        uint128 price = 2000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Create a long position to liquidate
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: liqPrice,
                price: price
            })
        );

        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.tickValue(desiredLiqTick, liqPrice);

        vm.expectEmit();
        emit LiquidatedTick(desiredLiqTick, 0, liqPrice, liqPriceAfterFundings, tickValue);

        // Set the tempVaultBalance parameter to less than tickValue to make sure it sends what it can
        LiquidationsEffects memory liquidationsEffects =
            protocol.i_liquidatePositions(uint256(liqPrice), 1, tickValue - 1, 100 ether);

        assertEq(liquidationsEffects.liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidationsEffects.liquidatedTicks.length, 1, "Only one tick should have been liquidated");
        assertEq(
            liquidationsEffects.remainingCollateral,
            tickValue,
            "The value of the tick should be the collateral liquidated"
        );
        assertEq(liquidationsEffects.newLongBalance, 0, "New long balance should be 0");
        assertEq(
            liquidationsEffects.newVaultBalance,
            100 ether + uint256(tickValue - 1),
            "New vault balance should be what was left in the longs"
        );
    }

    /**
     * @custom:scenario A position can be liquidated but there is not enough balance in the vault to cover
     * the debt to the longs
     * @custom:given A position with a value of X that can be liquidated
     * @custom:and A vault balance at X - 1
     * @custom:when User calls _liquidatePositions
     * @custom:then It should liquidate the position
     * @custom:and The vault balance should be at 0
     * @custom:and The long side should have absorbed the vault's debt
     */
    function test_canLiquidateEvenWithBadDebtInVault() public {
        vm.skip(true); // this case is not possible anymore with the new liquidation multiplier accumulator
        uint128 price = 3000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: liqPrice,
                price: price
            })
        );

        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(posId.tick);

        // Get a liquidation price that would cause a bad debt
        int24 liqTick = protocol.getEffectiveTickForPrice(liqPrice - 600 ether);
        price = protocol.getEffectivePriceForTick(liqTick);

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.tickValue(posId.tick, price);

        vm.expectEmit();
        emit LiquidatedTick(posId.tick, 0, price, liqPriceAfterFundings, tickValue);

        // Set the tempVaultBalance parameter to less than tickValue to make sure it sends what it can
        LiquidationsEffects memory liquidationsEffects =
            protocol.i_liquidatePositions(uint256(price), 1, 100 ether, tickValue);

        assertEq(liquidationsEffects.liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidationsEffects.liquidatedTicks.length, 1, "Only one tick should have been liquidated");
        assertEq(
            liquidationsEffects.remainingCollateral,
            tickValue,
            "The value of the tick should be the collateral liquidated"
        );
        assertEq(
            int256(liquidationsEffects.newLongBalance),
            100 ether + tickValue,
            "New long balance should be what was left in the vault"
        );
        assertEq(liquidationsEffects.newVaultBalance, 0, "New vault balance should be 0");
    }
}
