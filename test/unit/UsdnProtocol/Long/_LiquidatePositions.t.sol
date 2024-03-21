// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolLib } from "src/libraries/UsdnProtocolLib.sol";
import { TickMath } from "src/libraries/TickMath.sol";

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
    function test_nothingHappensWhenThereIsNothingToLiquidate() external {
        vm.recordLogs();
        (
            uint256 liquidatedPositions,
            uint16 liquidatedTicks,
            int256 remainingCollateral,
            uint256 newLongBalance,
            uint256 newVaultBalance
        ) = protocol.i_liquidatePositions(2000 ether, 1, 100 ether, 100 ether);
        uint256 logsAmount = vm.getRecordedLogs().length;

        assertEq(logsAmount, 0, "No event should have been emitted");
        assertEq(liquidatedPositions, 0, "No position should have been liquidated at the given price");
        assertEq(liquidatedTicks, 0, "No tick should have been liquidated at this price");
        assertEq(remainingCollateral, 0, "There should have been no changes to the collateral");
        assertEq(newLongBalance, 100 ether, "There should have been no changes to the long balance");
        assertEq(newVaultBalance, 100 ether, "There should have been no changes to the vault balance");
    }

    /**
     * @custom:scenario A position is underwater and can be liquidated
     * @custom:given A position has its liquidation price above current price
     * @custom:when User calls _liquidatePositions
     * @custom:then It should liquidate the position.
     */
    function test_canLiquidateAPosition() public {
        uint128 price = 2000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Create a long position to liquidate
        setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, liqPrice, price);

        uint128 liqPriceAfterFunding =
            UsdnProtocolLib.calcEffectivePriceForTick(desiredLiqTick, protocol.getLiquidationMultiplier());

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.i_tickValue(liqPrice, desiredLiqTick, protocol.getTotalExpoByTick(desiredLiqTick));

        vm.expectEmit();
        emit LiquidatedTick(desiredLiqTick, 0, liqPrice, liqPriceAfterFunding, tickValue);

        vm.recordLogs();
        (
            uint256 liquidatedPositions,
            uint16 liquidatedTicks,
            int256 collateralLiquidated,
            uint256 newLongBalance,
            uint256 newVaultBalance
        ) = protocol.i_liquidatePositions(uint256(liqPrice), 1, 100 ether, 100 ether);
        uint256 logsAmount = vm.getRecordedLogs().length;

        assertEq(logsAmount, 1, "Only one log should have been emitted");
        assertEq(liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidatedTicks, 1, "Only one tick should have been liquidated");
        assertEq(collateralLiquidated, tickValue, "Collateral liquidated should be equal to tickValue");
        assertEq(
            int256(newLongBalance), 100 ether - tickValue, "The long side should have paid tickValue to the vault side"
        );
        assertEq(
            int256(newVaultBalance), 100 ether + tickValue, "The long side should have paid tickValue to the vault side"
        );

        assertLt(
            protocol.getMaxInitializedTick(),
            desiredLiqTick,
            "The max Initialized tick should be lower than the last liquidated tick"
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
        uint128 price = 2000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Create a long position to liquidate
        setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, liqPrice, price);

        skip(34 days);
        protocol.i_applyPnlAndFunding(price, uint128(block.timestamp));

        uint128 liqPriceAfterFundings =
            UsdnProtocolLib.calcEffectivePriceForTick(desiredLiqTick, protocol.getLiquidationMultiplier());
        assertGt(
            liqPriceAfterFundings, price, "The fundings did not push the liquidation price above the current price"
        );

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.i_tickValue(price, desiredLiqTick, protocol.getTotalExpoByTick(desiredLiqTick));
        // Sanity check
        // Make sure we do not end up in a bad debt situation because of fundings
        assertGt(tickValue, 1, "Waited too long before liquidation, lower the skipped time");

        vm.expectEmit();
        emit LiquidatedTick(desiredLiqTick, 0, price, liqPriceAfterFundings, tickValue);
        (
            uint256 liquidatedPositions,
            uint16 liquidatedTicks,
            int256 collateralLiquidated,
            uint256 newLongBalance,
            uint256 newVaultBalance
        ) = protocol.i_liquidatePositions(price, 1, 100 ether, 100 ether);

        assertEq(liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidatedTicks, 1, "Only one tick should have been liquidated");
        assertEq(collateralLiquidated, tickValue, "Collateral liquidated should be equal to tickValue");
        assertEq(
            int256(newLongBalance), 100 ether - tickValue, "The long side should have paid tickValue to the vault side"
        );
        assertEq(
            int256(newVaultBalance), 100 ether + tickValue, "The long side should have paid tickValue to the vault side"
        );
    }

    /**
     * @custom:scenario The last position in the protocol is underwater and can be liquidated
     * @custom:given A position has its liquidation price above current price
     * @custom:when User calls _liquidatePositions with 2 iterations
     * @custom:then It should liquidate the position.
     */
    function test_canLiquidateTheLastPosition() public {
        int24 desiredLiqTick = 69_200;
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.i_tickValue(liqPrice, desiredLiqTick, protocol.getTotalExpoByTick(desiredLiqTick));

        vm.expectEmit();
        emit LiquidatedTick(desiredLiqTick, 0, liqPrice, liqPriceAfterFundings, tickValue);

        vm.recordLogs();
        // 2 Iterations to make sure we break the loop when there are no ticks to be found
        (uint256 liquidatedPositions,,,,) = protocol.i_liquidatePositions(uint256(liqPrice), 2, 100 ether, 100 ether);
        uint256 logsAmount = vm.getRecordedLogs().length;

        assertEq(logsAmount, 1, "Only one log should have been emitted");
        assertEq(liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(
            protocol.getMaxInitializedTick(),
            TickMath.minUsableTick(protocol.getTickSpacing()),
            "The max Initialized tick should be equal to the very last tick"
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
        int24 tickSpacing = protocol.getTickSpacing();
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice;

        // Iterate once more than the maximum of liquidations allowed
        int24[] memory ticksToLiquidate = new int24[](maxIterations + 1);
        for (uint16 i = 0; i < maxIterations + 1; ++i) {
            // Calculate the right tick for the iteration
            desiredLiqTick -= tickSpacing;
            liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick + 1);

            // Create a long position to liquidate
            setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, liqPrice, price);

            // Save the tick for future checks
            ticksToLiquidate[i] = desiredLiqTick;
        }

        // Expect MAX_LIQUIDATION_ITERATION events
        for (uint256 i = 0; i < maxIterations; ++i) {
            vm.expectEmit(true, true, false, false);
            emit LiquidatedTick(ticksToLiquidate[i], 0, 0, 0, 0);
        }

        // Set a price below all others
        liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick - 1);

        // Make sure no more than MAX_LIQUIDATION_ITERATION events have been emitted
        vm.recordLogs();
        (, uint256 liquidatedTicks,,,) =
            protocol.i_liquidatePositions(uint256(liqPrice), maxIterations + 1, 100 ether, 100 ether);
        uint256 logsAmount = vm.getRecordedLogs().length;

        assertEq(
            logsAmount, maxIterations, "An amount of events equal to MAX_LIQUIDATION_ITERATION should have been emitted"
        );

        assertEq(
            liquidatedTicks,
            maxIterations,
            "The amount of ticks liquidated should be equal to MAX_LIQUIDATION_ITERATION"
        );

        assertEq(
            protocol.getMaxInitializedTick(),
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
    function test_canLiquidateEvenWithBadDebtInLongs() external {
        uint128 price = 2000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Create a long position to liquidate
        setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, liqPrice, price);

        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.i_tickValue(liqPrice, desiredLiqTick, protocol.getTotalExpoByTick(desiredLiqTick));

        vm.expectEmit();
        emit LiquidatedTick(desiredLiqTick, 0, liqPrice, liqPriceAfterFundings, tickValue);

        // Set the tempVaultBalance parameter to less than tickValue to make sure it sends what it can
        (
            uint256 liquidatedPositions,
            uint16 liquidatedTicks,
            int256 collateralLiquidated,
            uint256 newLongBalance,
            uint256 newVaultBalance
        ) = protocol.i_liquidatePositions(uint256(liqPrice), 1, tickValue - 1, 100 ether);

        assertEq(liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidatedTicks, 1, "Only one tick should have been liquidated");
        assertEq(collateralLiquidated, tickValue, "The value of the tick should be the collateral liquidated");
        assertEq(newLongBalance, 0, "New long balance should be 0");
        assertEq(
            newVaultBalance,
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
    function test_canLiquidateEvenWithBadDebtInVault() external {
        uint128 price = 3000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        uint128 liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);

        // Create a long position to liquidate
        (int24 positionTick,,) =
            setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, liqPrice, price);

        uint128 liqPriceAfterFundings = protocol.getEffectivePriceForTick(positionTick);

        // Get a liquidation price that would cause a bad debt
        int24 liqTick = protocol.getEffectiveTickForPrice(liqPrice - 600 ether);
        price = protocol.getEffectivePriceForTick(liqTick);

        // Calculate the collateral this position gives on liquidation
        int256 tickValue = protocol.i_tickValue(price, positionTick, protocol.getTotalExpoByTick(positionTick));

        vm.expectEmit();
        emit LiquidatedTick(positionTick, 0, price, liqPriceAfterFundings, tickValue);

        // Set the tempVaultBalance parameter to less than tickValue to make sure it sends what it can
        (
            uint256 liquidatedPositions,
            uint16 liquidatedTicks,
            int256 collateralLiquidated,
            uint256 newLongBalance,
            uint256 newVaultBalance
        ) = protocol.i_liquidatePositions(uint256(price), 1, 100 ether, tickValue);

        assertEq(liquidatedPositions, 1, "Only one position should have been liquidated");
        assertEq(liquidatedTicks, 1, "Only one tick should have been liquidated");
        assertEq(collateralLiquidated, tickValue, "The value of the tick should be the collateral liquidated");
        assertEq(int256(newLongBalance), 100 ether + tickValue, "New long balance should be what was left in the vault");
        assertEq(newVaultBalance, 0, "New vault balance should be 0");
    }
}
