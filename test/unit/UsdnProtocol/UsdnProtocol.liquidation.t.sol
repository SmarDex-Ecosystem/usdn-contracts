// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/// @custom:feature The `_liquidatePositions` function of `UsdnProtocol`
contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /* @custom:scenario Simulate user open positions then 
     * a price drawdown and liquidations by other user action.
     * @custom:given User open positions 
     * @custom:and Block number increase 20
     * @custom:and Simulate a -20% asset price drawdown
     * @custom:when User execute any protocol action 
     * @custom:then Sould execute liquidations.
     * @custom:and Change contract state.
     */
    function test_openUserLiquidation() public {
        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(20 ether, true, protocol.getUsers(protocol.userCount()));
        assertEq(protocol.tickVersion(initialTick), 0, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 1_203_282_859_929_999_999_016, "wrong first totalExpo");
        // check if first tick hash match initial value
        assertEq(
            protocol.tickHash(initialTick),
            bytes32(
                uint256(
                    31_303_468_123_476_320_952_309_786_101_268_354_098_456_914_902_927_505_641_948_359_107_244_083_539_650
                )
            ),
            "wrong first tickHash"
        );
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 1_183_442_919_400_000_000_000, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 76_900, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint8 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);

        // second mock init open position
        protocol.mockInitiateOpenPosition(20 ether, true, protocol.getUsers(protocol.userCount() / 2));

        uint256 secondTickVersion = protocol.tickVersion(initialTick);
        // check if second tick version is updated properly
        assertEq(secondTickVersion, 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 606_574_924_429_999_999_016, "wrong second totalExpo");
        // check if second tick hash is equal expected value
        assertEq(
            protocol.tickHash(initialTick),
            bytes32(
                uint256(
                    112_445_457_736_805_415_271_282_785_611_942_110_906_241_620_093_834_231_219_694_755_927_915_188_543_033
                )
            ),
            "wrong second tickHash"
        );
        // check if second total expo by tick is equal expected value
        assertEq(protocol.totalExpoByTick(initialTick), 0, "wrong second totalExpoByTick");
        // check if second long position length is equal expected value
        assertEq(protocol.longPositionsLength(initialTick), 0, "wrong second longPositionsLength");
        // check if second position in tick is equal expected value
        assertEq(protocol.positionsInTick(initialTick), 0, "wrong second positionsInTick");
        // check if second max initialized is equal expected value
        assertEq(protocol.maxInitializedTick(), 74_600, "wrong second maxInitializedTick");
        // check if second total long positions is equal expected value
        assertEq(protocol.totalLongPositions(), 7, "wrong second totalLongPositions");
    }

    /* @custom:scenario Simulate user open positions then 
     * a price drawdown and liquidations by liquidators.
     * @custom:given User open positions 
     * @custom:and Block number increase 20
     * @custom:and Simulate a -20% asset price drawdown
     * @custom:when Liquidators execute liquidate 
     * @custom:then Sould execute liquidations.
     * @custom:and Change contract state.
     */
    function test_openLiquidatorLiquidation() public {
        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(20 ether, true, protocol.getUsers(protocol.userCount()));
        assertEq(protocol.tickVersion(initialTick), 0, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 1_203_282_859_929_999_999_016, "wrong first totalExpo");
        // check if first tick hash match initial value
        assertEq(
            protocol.tickHash(initialTick),
            bytes32(
                uint256(
                    31_303_468_123_476_320_952_309_786_101_268_354_098_456_914_902_927_505_641_948_359_107_244_083_539_650
                )
            ),
            "wrong first tickHash"
        );
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 1_183_442_919_400_000_000_000, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 76_900, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint8 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);
        // get price info
        (, bytes memory priceData) = protocol.getPriceInfo(block.number);
        // liquidator liquidation
        protocol.liquidate(priceData, 9);

        // check if second tick version is updated properly
        assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 19_839_940_529_999_999_016, "wrong second totalExpo");
        // check if second tick hash is equal expected value
        assertEq(
            protocol.tickHash(initialTick),
            bytes32(
                uint256(
                    112_445_457_736_805_415_271_282_785_611_942_110_906_241_620_093_834_231_219_694_755_927_915_188_543_033
                )
            ),
            "wrong second tickHash"
        );
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
}
