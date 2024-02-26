// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature The `_liquidatePositions` function of `UsdnProtocol`
contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);

        chainlinkGasPriceFeed.setLatestRoundData(1, 30 gwei, block.timestamp, 1);
        vm.txGasPrice(30 gwei);
    }

    /**
     * @custom:scenario Simulate user open positions then
     * a price drawdown and liquidations by other user action.
     * @custom:given User open positions
     * @custom:and Simulate a price drawdown
     * @custom:when User execute any protocol action
     * @custom:then Should execute liquidations.
     * @custom:and Change contract state.
     */
    function test_openUserLiquidation() public {
        bytes memory priceData = abi.encode(2000 ether);
        int24 initialTick;
        uint256 initialTickVersion;

        for (uint256 i; i < 10; i++) {
            vm.startPrank(users[i]);
            (initialTick, initialTickVersion,) = protocol.initiateOpenPosition(5 ether, 1700 ether, priceData, "");
            protocol.validateOpenPosition(priceData, "");
            vm.stopPrank();
        }

        assertEq(protocol.tickVersion(initialTick), initialTickVersion, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 297.551622685266578822 ether, "wrong first totalExpo");
        // check if first tick match initial value
        assertEq(initialTick, 74_300, "wrong first tick");
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 287.63165241556311665 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_300, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        skip(1 hours);
        priceData = abi.encode(1650 ether);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(
            74_300, 0, 1650 ether, 1_690_036_391_607_383_729_990, -1_145_834_789_258_790_464
        );
        // initiate a position to liquidate all other positions
        protocol.initiateOpenPosition(5 ether, 500 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        // check if second tick version is updated properly
        assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 17.021693501698224247 ether, "wrong second totalExpo");
        // check if second total expo by tick is equal expected value
        assertEq(protocol.totalExpoByTick(initialTick), 0, "wrong second totalExpoByTick");
        // check if second long position length is equal expected value
        assertEq(protocol.longPositionsLength(initialTick), 0, "wrong second longPositionsLength");
        // check if second position in tick is equal expected value
        assertEq(protocol.positionsInTick(initialTick), 0, "wrong second positionsInTick");
        // check if second max initialized is equal expected value
        assertEq(protocol.maxInitializedTick(), 69_200, "wrong second maxInitializedTick");
        // check if second total long positions is equal expected value
        assertEq(protocol.totalLongPositions(), 3, "wrong second totalLongPositions");
    }

    /**
     * @custom:scenario Simulate user open positions then
     * a price drawdown and liquidations by liquidators with above max iteration.
     * @custom:given User open positions
     * @custom:and Block number increase 20
     * @custom:and Simulate a -20% asset price drawdown
     * @custom:when Liquidators execute liquidate
     * @custom:then Should execute liquidations.
     * @custom:and Change contract state.
     */
    function test_openLiquidatorLiquidation() public {
        bytes memory priceData = abi.encode(2000 ether);
        int24 initialTick;
        uint256 initialTickVersion;

        for (uint256 i; i < 10; i++) {
            vm.startPrank(users[i]);
            (initialTick, initialTickVersion,) = protocol.initiateOpenPosition(5 ether, 1700 ether, priceData, "");
            protocol.validateOpenPosition(priceData, "");
            vm.stopPrank();
        }

        assertEq(protocol.tickVersion(initialTick), initialTickVersion, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 297.551622685266578822 ether, "wrong first totalExpo");
        // check if first tick match initial value
        assertEq(initialTick, 74_300, "wrong first tick");
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 287.63165241556311665 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_300, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        skip(1 hours);
        priceData = abi.encode(1000 ether);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(
            74_300, 0, 1000 ether, 1_693_843_416_978_052_801_721, -189_924_540_675_293_261_973
        );
        // liquidator liquidation
        protocol.liquidate(priceData, 9);

        // check if second tick version is updated properly
        assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 1000, "wrong second totalExpo");
        // check if second total expo by tick is equal expected value
        assertEq(protocol.totalExpoByTick(initialTick), 0, "wrong second totalExpoByTick");
        // check if second long position length is equal expected value
        assertEq(protocol.longPositionsLength(initialTick), 0, "wrong second longPositionsLength");
        // check if second position in tick is equal expected value
        assertEq(protocol.positionsInTick(initialTick), 0, "wrong second positionsInTick");
        // check if second max initialized is equal expected value
        assertEq(protocol.maxInitializedTick(), -322_300, "wrong second maxInitializedTick");
        // check if second total long positions is equal expected value
        assertEq(protocol.totalLongPositions(), 1, "wrong second totalLongPositions");
    }

    /**
     * @custom:scenario Simulate user open positions on many different tick then
     * a price drawdown and liquidations by liquidators.
     * @custom:given User open positions
     * @custom:and Simulate a 20 price drawdown
     * @custom:when Liquidators execute liquidate once
     * @custom:then Should execute liquidations partially.
     * @custom:and Change contract state.
     * @custom:when Liquidators execute liquidate many time
     * @custom:then Should execute liquidations entirely.
     * @custom:and Change contract state.
     */
    function test_openLiquidatorPartialLiquidation() public {
        uint256 length = users.length;
        int24[] memory initialTicks = new int24[](length);
        uint256 actualPrice = 2000 ether;
        bytes memory priceData = abi.encode(actualPrice);

        for (uint256 i; i < length; i++) {
            vm.startPrank(users[i]);
            (initialTicks[i],,) =
                protocol.initiateOpenPosition(20 ether, uint128(actualPrice * 80 / 100), priceData, "");
            protocol.validateOpenPosition(priceData, "");
            vm.stopPrank();
            // 20 eth drawdown
            actualPrice -= 20 ether;
            priceData = abi.encode(actualPrice);
            skip(1 hours);
        }

        // check if positions aren't liquidated
        for (uint256 i; i != length; i++) {
            // check if first tickVersion match initial value
            assertEq(protocol.tickVersion(initialTicks[i]), 0, "wrong first tickVersion");
            // check if first long position length match initial value
            assertEq(protocol.longPositionsLength(initialTicks[i]), 1, "wrong first longPositionsLength");
            // check if first position in tick match initial value
            assertEq(protocol.positionsInTick(initialTicks[i]), 1, "wrong first positionsInTick");
        }
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 925.733405461108874572 ether, "wrong first totalExpo");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 73_700, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        priceData = abi.encode(1000 ether);

        skip(1 hours);
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(
            73_700, 0, 1000 ether, 1_673_354_200_091_317_811_030, -57_694_526_575_135_275_414
        );
        // liquidator first liquidation batch
        protocol.liquidate(priceData, uint16(length / 2));

        // half users should be liquidated
        for (uint256 i; i != length / 2; i++) {
            // check if second tickVersion is updated
            assertEq(protocol.tickVersion(initialTicks[i]), 1, "wrong second tickVersion");
            // check if second long position is updated
            assertEq(protocol.longPositionsLength(initialTicks[i]), 0, "wrong second longPositionsLength");
            // check if second long position is updated
            assertEq(protocol.positionsInTick(initialTicks[i]), 0, "wrong second positionsInTick");
        }

        // check if second total expo match expected value
        assertEq(protocol.totalExpo(), 468.70124431461574664 ether, "wrong second totalExpo");
        // check if second max initialized match expected value
        assertEq(protocol.maxInitializedTick(), 73_000, "wrong second maxInitializedTick");
        // check if second total long positions match expected value
        assertEq(protocol.totalLongPositions(), 7, "wrong second totalLongPositions");

        // liquidator second liquidation batch
        protocol.liquidate(priceData, uint16(length / 2));

        // all users should be liquidated
        for (uint256 i = length / 2; i != length; i++) {
            // check if second tickVersion is updated
            assertEq(protocol.tickVersion(initialTicks[i]), 1, "wrong second tickVersion in tick");
            // check if second long position is updated
            assertEq(protocol.longPositionsLength(initialTicks[i]), 0, "wrong second longPositionsLength in tick");
            // check if second long position is updated
            assertEq(protocol.positionsInTick(initialTicks[i]), 0, "wrong second positionsInTick in tick");
        }

        // check if second total expo match expected value
        assertEq(protocol.totalExpo(), 9.919970269703462172 ether, "wrong second totalExpo");
        // check if second max initialized match expected value
        assertEq(protocol.maxInitializedTick(), 69_200, "wrong second maxInitializedTick");
        // check if second total long positions match expected value
        assertEq(protocol.totalLongPositions(), 2, "wrong second totalLongPositions");
    }

    /**
     * @custom:scenario Simulate user open positions on many different tick then
     * a price drawdown and liquidation with maxLiquidationIteration + 1
     * @custom:given Users open positions
     * @custom:and Simulate a 50% price drawdown
     * @custom:when Liquidators execute liquidate with maxLiquidationIteration + 1
     * @custom:then Only the max number of liquidations are executed
     * @custom:and The liquidator receive rewards in connection with the amount of ticks liquidated
     */
    function test_openLiquidatorLiquidationAboveMax() public {
        bytes memory priceData = abi.encode(2000 ether);
        int24 initialTick;
        uint256 initialTickVersion;

        for (uint256 i; i < 10; i++) {
            vm.startPrank(users[i]);
            (initialTick, initialTickVersion,) = protocol.initiateOpenPosition(5 ether, 1700 ether, priceData, "");
            protocol.validateOpenPosition(priceData, "");
            vm.stopPrank();
        }

        // max liquidation iteration constant
        uint16 maxLiquidationIteration = protocol.maxLiquidationIteration();
        // check if first tick version match initial value
        assertEq(protocol.tickVersion(initialTick), initialTickVersion, "wrong first tickVersion");

        skip(1 hours);
        priceData = abi.encode(1000 ether);
        protocol.liquidate(priceData, maxLiquidationIteration + 1);

        // check if second tick version is updated properly
        assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
    }

    /**
     * @custom:scenario A position gets liquidated due to funding rates without price change
     * @custom:given A small high risk position (leverage ~10x) and a very large low risk position (leverage ~2x)
     * @custom:and A large imbalance in the trading expo of the long side vs vault side
     * @custom:when We wait for 4 days and the price stays contant
     * @custom:and We then call `liquidate`
     * @custom:then Funding rates make the liquidation price of the high risk positions go up (the liquidation
     * multiplier increases)
     * @custom:and The high risk position gets liquidated even though the asset price has not changed
     */
    function test_liquidatedByFundingRates() public {
        uint128 currentPrice = 2000 ether;

        wstETH.mintAndApprove(address(this), 1_000_000 ether, address(protocol), type(uint256).max);

        bytes memory priceData = abi.encode(uint128(currentPrice));

        // create high risk position
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(5 ether, 9 * currentPrice / 10, priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");

        // create large low-risk position to affect funding rates
        protocol.initiateOpenPosition(500_000 ether, currentPrice / 2, priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");

        uint256 initialMultiplier = protocol.liquidationMultiplier();

        uint128 liqPrice = protocol.getEffectivePriceForTick(tick);
        assertLt(liqPrice, currentPrice, "liquidation price >= current price");

        // Wait 1 day so that funding rates make the liquidation price of those positions go up
        skip(1 days);

        // Adjust balances, multiplier and liquidate positions
        uint256 liquidated = protocol.liquidate(priceData, 0);

        // the liquidation price for the high risk position went above the current price
        assertEq(liquidated, 1, "liquidation failed");
        liqPrice = protocol.getEffectivePriceForTick(tick);
        assertGt(liqPrice, currentPrice, "liquidation price <= current price");
        assertGt(protocol.liquidationMultiplier(), initialMultiplier, "multiplier did not grow");

        // the position doesn't exist anymore
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, tickVersion + 1, tickVersion));
        protocol.getLongPosition(tick, tickVersion, index);
    }

    /**
     * @custom:scenario A liquidator receives no rewards if liquidate() is called but no ticks can be liquidated
     * @custom:given There are no ticks that can be liquidated
     * @custom:when A liquidator calls the function liquidate()
     * @custom:then No rewards are sent and no ticks are liquidated
     */
    function test_nothingHappensIfNoTicksCanBeLiquidated() public {
        bytes memory priceData = abi.encode(2000 ether);

        vm.startPrank(users[0]);
        protocol.initiateOpenPosition(5 ether, 1700 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        vm.stopPrank();

        priceData = abi.encode(1950 ether);

        uint256 wstETHBalanceBeforeRewards = wstETH.balanceOf(address(this));
        uint256 vaultBalanceBeforeRewards = protocol.balanceVault();
        uint256 longPositionsBeforeLiquidation = protocol.totalLongPositions();

        protocol.liquidate(priceData, 1);

        // check that the liquidator didn't receive any rewards
        assertEq(
            wstETHBalanceBeforeRewards,
            wstETH.balanceOf(address(this)),
            "The liquidator should not receive rewards if there were no liquidations"
        );

        // check that the vault balance did not change
        assertEq(
            vaultBalanceBeforeRewards,
            protocol.balanceVault(),
            "The vault balance should not change if there were no liquidations"
        );

        // check if first total long positions match initial value
        assertEq(
            longPositionsBeforeLiquidation,
            protocol.totalLongPositions(),
            "The number of long positions should not have changed"
        );
    }

    /**
     * @custom:scenario A liquidator liquidate a tick and receive a reward
     * @custom:given There is a tick that can be liquidated
     * @custom:when A liquidator calls the function liquidate()
     * @custom:then The protocol send rewards for the liquidation
     */
    function test_rewardsAreSentToLiquidatorAfterLiquidations() public {
        bytes memory priceData = abi.encode(2000 ether);

        vm.startPrank(users[0]);
        protocol.initiateOpenPosition(5 ether, 1700 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        vm.stopPrank();

        // Change The rewards calculations parameters to not be dependent of the initial values
        vm.prank(DEPLOYER);
        liquidationRewardsManager.setRewardsParameters(10_000, 30_000, 1000 gwei, 20_000);

        priceData = abi.encode(1680 ether);

        uint256 collateralLiquidated = 473_682_811_132_131_111;
        uint256 expectedLiquidatorRewards = 4_209_000_000_000_000;
        uint256 wstETHBalanceBeforeRewards = wstETH.balanceOf(address(this));
        uint256 vaultBalanceBeforeRewards = protocol.balanceVault();

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.liquidate(priceData, 1);

        // check that the liquidator received its rewards
        assertEq(
            wstETH.balanceOf(address(this)) - wstETHBalanceBeforeRewards,
            expectedLiquidatorRewards,
            "The liquidator did not receive the right amount of rewards"
        );

        // check that the vault balance got updated
        assertEq(
            vaultBalanceBeforeRewards + collateralLiquidated - protocol.balanceVault(),
            expectedLiquidatorRewards,
            "The vault does not contain the right amount of funds"
        );
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are one or more ticks that can be liquidated
     * @custom:when A liquidator calls the function liquidate
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_gasUsageOfLiquidateFunction() public {
        bytes memory priceData = abi.encode(4500 ether);

        vm.startPrank(users[0]);
        protocol.initiateOpenPosition(1 ether, 4000 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        protocol.initiateOpenPosition(1 ether, 3950 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        protocol.initiateOpenPosition(1 ether, 3900 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        vm.stopPrank();

        ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters memory rewardsParameters =
            liquidationRewardsManager.getRewardsParameters();

        uint256 snapshotId = vm.snapshot();

        uint256[] memory gasUsedArray = new uint256[](3);
        for (uint16 ticksToLiquidate = 1; ticksToLiquidate <= 3; ++ticksToLiquidate) {
            // Get a price that liquidates `ticksToLiquidate` ticks
            priceData = abi.encode(4010 ether - (50 ether * ticksToLiquidate));

            uint256 startGas = gasleft();
            uint256 positionsLiquidated = protocol.liquidate(priceData, ticksToLiquidate);
            uint256 gasUsed = startGas - gasleft();
            gasUsedArray[ticksToLiquidate - 1] = gasUsed;

            // Make sure the expected amount of computation was executed
            assertEq(
                positionsLiquidated,
                ticksToLiquidate,
                "We expect 1, 2 or 3 positions liquidated depending on the iteration"
            );

            vm.revertTo(snapshotId);
        }

        // Calculate the average gas used exclusively by a loop of tick liquidation
        uint256 averageGasUsedPerTick = (gasUsedArray[1] - gasUsedArray[0] + gasUsedArray[2] - gasUsedArray[1]) / 2;
        // Calculate the average gas used by everything BUT loops of tick liquidation
        uint256 averageOtherGasUsed = (
            gasUsedArray[0] - averageGasUsedPerTick + gasUsedArray[1] - (averageGasUsedPerTick * 2) + gasUsedArray[2]
                - (averageGasUsedPerTick * 3)
        ) / 3;

        // Check that the gas usage per tick matches the gasUsedPerTick parameter in the LiquidationRewardsManager
        assertEq(
            averageGasUsedPerTick,
            rewardsParameters.gasUsedPerTick,
            "The result should match the gasUsedPerTick parameter set in LiquidationRewardsManager's constructor"
        );
        // Check that the other gas usage matches the otherGasUsed parameter in the LiquidationRewardsManager
        assertEq(
            averageOtherGasUsed,
            rewardsParameters.otherGasUsed,
            "The result should match the otherGasUsed parameter set in LiquidationRewardsManager's constructor"
        );
    }

    /**
     * @custom:scenario The user sends too much ether when liquidating positions
     * @custom:given The user performs a liquidation
     * @custom:when The user sends 0.5 ether as value in the `liquidate` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_liquidateEtherRefund() public {
        uint256 initialTotalPos = protocol.totalLongPositions();
        uint128 currentPrice = 2000 ether;
        bytes memory priceData = abi.encode(currentPrice);

        wstETH.mintAndApprove(address(this), 1_000_000 ether, address(protocol), type(uint256).max);

        // create high risk position
        protocol.initiateOpenPosition{
            value: oracleMiddleware.validationCost(priceData, ProtocolAction.InitiateOpenPosition)
        }(5 ether, 9 * currentPrice / 10, priceData, "");
        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost(priceData, ProtocolAction.ValidateOpenPosition)
        }(priceData, "");
        assertEq(protocol.totalLongPositions(), initialTotalPos + 1, "total positions after create");

        // price drops
        skip(1 hours);
        currentPrice = 1000 ether;
        priceData = abi.encode(currentPrice);

        // liquidate
        uint256 balanceBefore = address(this).balance;
        uint256 validationCost = oracleMiddleware.validationCost(priceData, ProtocolAction.Liquidation);
        protocol.liquidate{ value: 0.5 ether }(priceData, 1);
        assertEq(protocol.totalLongPositions(), initialTotalPos, "total positions after liquidate");
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    // test refunds
    receive() external payable { }
}
