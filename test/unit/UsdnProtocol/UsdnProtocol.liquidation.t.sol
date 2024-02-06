// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";

/// @custom:feature The `_liquidatePositions` function of `UsdnProtocol`
contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    using Strings for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /* @custom:scenario Simulate user open positions then
     * a price drawdown and liquidations by other user action.
     * @custom:given User open positions
     * @custom:and Block number increase 20
     * @custom:and Simulate a -20% asset price drawdown
     * @custom:when User execute any protocol action
     * @custom:then Should execute liquidations.
     * @custom:and Change contract state.
     */
    function test_openUserLiquidation() public {
        // mock initiate open
        (int24 initialTick, uint256 initialTickVersion) =
            mockInitiateOpenPosition(20 ether, true, getUsers(users.length));
        // for (uint256 i; i < 10; i++) {
        //     // liquidation target price -15%
        //     uint128 liquidationTargetPriceUint = currentPrice * 85 / 100;

        //     vm.startPrank(_users[i]);
        //     // initiate open position
        //     (tick_, tickVersion_,) = protocol.initiateOpenPosition(refAmount, liquidationTargetPriceUint, priceData,
        // "");

        //     // if auto validate true
        //     if (autoValidate) {
        //         // auto validate open position
        //         protocol.validateOpenPosition(priceData, priceData);
        //     }

        //     vm.stopPrank();
        // }
        assertEq(protocol.tickVersion(initialTick), initialTickVersion, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 1283.887326349043056207 ether, "wrong first totalExpo");
        // check if first tick match initial value
        assertEq(initialTick, 74_300, "wrong first tick");
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 1273.967356079339594035 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_300, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint256 blockDiff = 90;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff);

        // get price info
        (uint256 price,) = getPriceInfo(block.number);

        // @fireboss777 TODO : tick isn't liquidated anymore with new funding rate
        // vm.expectEmit();
        // emit IUsdnProtocolEvents.LiquidatedTick(74_300, 0, price, 1_685_686_755_561_908_164_436);
        // // second mock init open position
        // emit log_named_uint("user lenght", users.length / 2);
        // mockInitiateOpenPosition(20 ether, true, getUsers(users.length / 2));

        // // check if second tick version is updated properly
        // assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
        // // check if second total expo is equal expected value
        // assertEq(protocol.totalExpo(), 641.065993449946923772 ether, "wrong second totalExpo");
        // // check if second total expo by tick is equal expected value
        // assertEq(protocol.totalExpoByTick(initialTick), 0, "wrong second totalExpoByTick");
        // // check if second long position length is equal expected value
        // assertEq(protocol.longPositionsLength(initialTick), 0, "wrong second longPositionsLength");
        // // check if second position in tick is equal expected value
        // assertEq(protocol.positionsInTick(initialTick), 0, "wrong second positionsInTick");
        // // check if second max initialized is equal expected value
        // assertEq(protocol.maxInitializedTick(), 72_000, "wrong second maxInitializedTick");
        // // check if second total long positions is equal expected value
        // assertEq(protocol.totalLongPositions(), 7, "wrong second totalLongPositions");
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
        // mock initiate open
        (int24 initialTick, uint256 initialTickVersion) =
            mockInitiateOpenPosition(20 ether, true, getUsers(users.length));
        assertEq(protocol.tickVersion(initialTick), initialTickVersion, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 1283.887326349043056207 ether, "wrong first totalExpo");
        // check if first tick match initial value
        assertEq(initialTick, 74_300, "wrong first tick");
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 1273.967356079339594035 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_300, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint8 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);
        // get price info
        (uint256 price, bytes memory priceData) = getPriceInfo(block.number);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(74_300, 0, price, 1_686_635_265_697_966_620_612);
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
     * @custom:and Block number increase 20
     * @custom:and Simulate a -20% asset price drawdown
     * @custom:when Liquidators execute liquidate once
     * @custom:then Should execute liquidations partially.
     * @custom:and Change contract state.
     * @custom:when Liquidators execute liquidate many time
     * @custom:then Should execute liquidations entirely.
     * @custom:and Change contract state.
     */
    function test_openLiquidatorPartialLiquidation() public {
        // get all funded users
        address[] memory allUsers = getUsers(users.length);
        // users count
        uint256 length = allUsers.length;
        // sorted user array
        address[][] memory splitUsers = new address[][](length);
        // users split into many single user arrays
        for (uint256 i; i != length; i++) {
            // array of unique user
            address[] memory standaloneUser = new address[](1);
            // store user
            standaloneUser[0] = allUsers[i];
            // store array
            splitUsers[i] = standaloneUser;
        }

        // array of initials tick by user
        int24[] memory initialTicks = new int24[](length);

        // all open positions
        for (uint256 i; i != length; i++) {
            // open user position and store related initial tick
            (initialTicks[i],) = mockInitiateOpenPosition(20 ether, true, splitUsers[i]);
            // block change to move price below
            uint8 blockJump = 1;
            // increment 1 block (1% drawdown)
            vm.roll(block.number + blockJump);
            // increment timestamp equivalent required by pnl
            vm.warp(block.timestamp + blockJump * 12);
        }

        // check if positions aren't liquidated
        for (uint256 i; i != length; i++) {
            // check if first tickVersion
            // match initial value
            assertEq(
                protocol.tickVersion(initialTicks[i]),
                0,
                string.concat(
                    "wrong first tickVersion of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
            // check if first long position
            // length match initial value
            assertEq(
                protocol.longPositionsLength(initialTicks[i]),
                1,
                string.concat(
                    "wrong first longPositionsLength of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
            // check if first position
            // in tick match initial value
            assertEq(
                protocol.positionsInTick(initialTicks[i]),
                1,
                string.concat(
                    "wrong first positionsInTick of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
        }
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 1302.348650123719069234 ether, "wrong first totalExpo");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_300, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint16 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);
        // get price info
        (uint256 price, bytes memory priceData) = getPriceInfo(block.number);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(74_300, 0, price, 1_691_456_338_796_793_261_384);

        // liquidator first liquidation batch
        protocol.liquidate(priceData, uint16(length / 2));

        // half users should be liquidated
        for (uint256 i; i != length / 2; i++) {
            // check if second tickVersion is updated
            assertEq(
                protocol.tickVersion(initialTicks[i]),
                1,
                string.concat(
                    "wrong second tickVersion of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
            // check if second long position is updated
            assertEq(
                protocol.longPositionsLength(initialTicks[i]),
                0,
                string.concat(
                    "wrong second longPositionsLength of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
            // check if second long position is updated
            assertEq(
                protocol.positionsInTick(initialTicks[i]),
                0,
                string.concat(
                    "wrong second positionsInTick of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
        }

        // check if second total expo match expected value
        assertEq(protocol.totalExpo(), 661.64668717948324396 ether, "wrong second totalExpo");
        // check if second max initialized match expected value
        assertEq(protocol.maxInitializedTick(), 73_800, "wrong second maxInitializedTick");
        // check if second total long positions match expected value
        assertEq(protocol.totalLongPositions(), 7, "wrong second totalLongPositions");

        // liquidator second liquidation batch
        protocol.liquidate(priceData, uint16(length / 2));

        // all users should be liquidated
        for (uint256 i = length / 2; i != length; i++) {
            // check if second tickVersion is updated
            assertEq(
                protocol.tickVersion(initialTicks[i]),
                1,
                string.concat(
                    "wrong second tickVersion of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
            // check if second long position is updated
            assertEq(
                protocol.longPositionsLength(initialTicks[i]),
                0,
                string.concat(
                    "wrong second longPositionsLength of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
            // check if second long position is updated
            assertEq(
                protocol.positionsInTick(initialTicks[i]),
                0,
                string.concat(
                    "wrong second positionsInTick of user index ",
                    i.toString(),
                    " in tick ",
                    uint256(uint24(initialTicks[i])).toString()
                )
            );
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
        // mock initiate open
        (int24 initialTick, uint256 initialTickVersion) =
            mockInitiateOpenPosition(20 ether, true, getUsers(users.length));
        // max liquidation iteration constant
        uint16 maxLiquidationIteration = protocol.maxLiquidationIteration();
        // check if first tick version match initial value
        assertEq(protocol.tickVersion(initialTick), initialTickVersion, "wrong first tickVersion");

        uint8 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);
        // get price info
        (, bytes memory priceData) = getPriceInfo(block.number);
        // liquidator liquidation
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
