// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";

/// @custom:feature The `_liquidatePositions` function of `UsdnProtocol`
contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mint(address(this), 100_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    /* @custom:scenario Simulate user open positions then
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
        assertEq(protocol.totalExpo(), 328.047029410564257445 ether, "wrong first totalExpo");
        // check if first tick match initial value
        assertEq(initialTick, 74_500, "wrong first tick");
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 318.127059140860795273 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_500, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        skip(1 hours);
        priceData = abi.encode(1000 ether);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(74_500, 0, 1000 ether, 1_723_571_392_504_943_895_629);
        // initiate a position to liquidate all other positions
        protocol.initiateOpenPosition(5 ether, 500 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        // check if second tick version is updated properly
        assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 19.896132875403854163 ether, "wrong second totalExpo");
        // check if second total expo by tick is equal expected value
        assertEq(protocol.totalExpoByTick(initialTick), 0, "wrong second totalExpoByTick");
        // check if second long position length is equal expected value
        assertEq(protocol.longPositionsLength(initialTick), 0, "wrong second longPositionsLength");
        // check if second position in tick is equal expected value
        assertEq(protocol.positionsInTick(initialTick), 0, "wrong second positionsInTick");
        // check if second max initialized is equal expected value
        assertEq(protocol.maxInitializedTick(), 69_000, "wrong second maxInitializedTick");
        // check if second total long positions is equal expected value
        assertEq(protocol.totalLongPositions(), 3, "wrong second totalLongPositions");
    }

    /* @custom:scenario Simulate user open positions then
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
        assertEq(protocol.totalExpo(), 328.047029410564257445 ether, "wrong first totalExpo");
        // check if first tick match initial value
        assertEq(initialTick, 74_500, "wrong first tick");
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 318.127059140860795273 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_500, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        skip(1 hours);
        priceData = abi.encode(1000 ether);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(74_500, 0, 1000 ether, 1_726_950_570_165_759_879_975);
        // liquidator liquidation
        protocol.liquidate(priceData, 9);

        // check if second tick version is updated properly
        assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 9.919970269703462172 ether, "wrong second totalExpo");
        // check if second total expo by tick is equal expected value
        assertEq(protocol.totalExpoByTick(initialTick), 0, "wrong second totalExpoByTick");
        // check if second long position length is equal expected value
        assertEq(protocol.longPositionsLength(initialTick), 0, "wrong second longPositionsLength");
        // check if second position in tick is equal expected value
        assertEq(protocol.positionsInTick(initialTick), 0, "wrong second positionsInTick");
        // check if second max initialized is equal expected value
        assertEq(protocol.maxInitializedTick(), 69_000, "wrong second maxInitializedTick");
        // check if second total long positions is equal expected value
        assertEq(protocol.totalLongPositions(), 2, "wrong second totalLongPositions");
    }

    /* @custom:scenario Simulate user open positions on many different tick then
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
        assertEq(protocol.totalExpo(), 988.159142722108529164 ether, "wrong first totalExpo");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 73_900, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        priceData = abi.encode(1000 ether);
        skip(1 hours);
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(73_900, 0, 1000 ether, 1_705_284_456_249_303_267_156);
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
        assertEq(protocol.totalExpo(), 499.595470847247780362 ether, "wrong second totalExpo");
        // check if second max initialized match expected value
        assertEq(protocol.maxInitializedTick(), 73_200, "wrong second maxInitializedTick");
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
        assertEq(protocol.maxInitializedTick(), 69_000, "wrong second maxInitializedTick");
        // check if second total long positions match expected value
        assertEq(protocol.totalLongPositions(), 2, "wrong second totalLongPositions");
    }

    /* @custom:scenario Simulate user open positions then
     * a price drawdown and liquidations by liquidators.
     * @custom:given User open positions
     * @custom:and Block number increase 20
     * @custom:and Simulate a -20% asset price drawdown
     * @custom:when Liquidators execute liquidate
     * @custom:then Should execute liquidations.
     * @custom:and Change contract state.
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

        wstETH.mint(address(this), 1_000_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);

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
        assertLt(liqPrice, currentPrice);

        // Wait 1 day so that funding rates make the liquidation price of those positions go up
        skip(1 days);

        // Adjust balances, multiplier and liquidate positions
        uint256 liquidated = protocol.liquidate(priceData, 0);

        assertEq(liquidated, 1); // the liquidation price for the high risk position went above the current price
        liqPrice = protocol.getEffectivePriceForTick(tick);
        assertGt(liqPrice, currentPrice);
        assertGt(protocol.liquidationMultiplier(), initialMultiplier);

        // the position doesn't exist anymore
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, tickVersion + 1, tickVersion));
        protocol.getLongPosition(tick, tickVersion, index);
    }
}
