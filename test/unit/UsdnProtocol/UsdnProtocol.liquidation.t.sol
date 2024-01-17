// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /* @custom:scenario Simulate user open positions.
     * @custom:when Block number increase 20, simulate a -20% 
     * asset price drawdown and user any protocol action 
     * should execute liquidation.
     * @custom:then Tick version should be incremented.
     */
    function test_openUserLiquidation() public {
        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(true, protocol.getUsers(protocol.userCount()));
        // first mock init open position
        uint256 firstTickVersion = protocol.tickVersion(initialTick);
        assertEq(firstTickVersion, 0, "wrong firstTickVersion");
        // first total expo
        uint256 firstTotalExpo = protocol.totalExpo();
        // check if first total expo match initial value
        assertEq(firstTotalExpo, 1_203_282_859_929_999_999_016, "wrong firstTotalExpo");
        // first tick hash
        bytes32 firstTickHash = protocol.tickHash(initialTick);
        // check if first tick hash match initial value
        assertEq(
            firstTickHash,
            bytes32(
                uint256(
                    31_303_468_123_476_320_952_309_786_101_268_354_098_456_914_902_927_505_641_948_359_107_244_083_539_650
                )
            ),
            "wrong firstTickHash"
        );
        // first total expo by tick
        uint256 firstTotalExpoByTick = protocol.totalExpoByTick(initialTick);
        // check if first total expo by tick match initial value
        assertEq(firstTotalExpoByTick, 1_183_442_919_400_000_000_000, "wrong firstTotalExpoByTick");
        // first long position length
        uint256 firstLongPositionsLengthByTick = protocol.longPositionsLength(initialTick);
        // check if first long position length match initial value
        assertEq(firstLongPositionsLengthByTick, 10, "wrong firstLongPositionsLengthByTick");
        // first position in tick
        uint256 firstPositionsInTick = protocol.positionsInTick(initialTick);
        // check if first position in tick match initial value
        assertEq(firstPositionsInTick, 10, "wrong firstPositionsInTick");
        // first max initialized tick
        int24 firstMaxInitializedTick = protocol.maxInitializedTick();
        // check if first max initialized match initial value
        assertEq(firstMaxInitializedTick, 76_900, "wrong firstMaxInitializedTick");
        // first total long positions
        uint256 firstTotalLongPositions = protocol.totalLongPositions();
        // check if first total long positions match initial value
        assertEq(firstTotalLongPositions, 12, "wrong firstTotalLongPositions");

        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + 20); // block number
        // second mock init open position
        protocol.mockInitiateOpenPosition(true, protocol.getUsers(protocol.userCount() / 2));

        // to avoid stack too deep
        {
            // second tick version
            uint256 secondTickVersion = protocol.tickVersion(initialTick);
            // check if second tick version is updated properly
            assertEq(secondTickVersion, 1, "wrong secondTickVersion");
            // second total expo
            uint256 secondTotalExpo = protocol.totalExpo();
            // check if second total expo is equal expected value
            assertEq(secondTotalExpo, 606_574_924_429_999_999_016, "wrong secondTotalExpo");
            // second tick hash
            bytes32 secondTickHash = protocol.tickHash(initialTick);
            // check if second tick hash is equal expected value
            assertEq(
                secondTickHash,
                bytes32(
                    uint256(
                        112_445_457_736_805_415_271_282_785_611_942_110_906_241_620_093_834_231_219_694_755_927_915_188_543_033
                    )
                ),
                "wrong secondTickHash"
            );
            // second total expo by tick
            uint256 secondTotalExpoByTick = protocol.totalExpoByTick(initialTick);
            // check if second total expo by tick is equal expected value
            assertEq(secondTotalExpoByTick, 0, "wrong secondTotalExpoByTick");
            // second long position length
            uint256 secondLongPositionsLengthByTick = protocol.longPositionsLength(initialTick);
            // check if second long position length is equal expected value
            assertEq(secondLongPositionsLengthByTick, 0, "wrong secondLongPositionsLengthByTick");
        }

        // to avoid stack too deep
        {
            // second position in tick
            uint256 secondPositionsInTick = protocol.positionsInTick(initialTick);
            // check if second position in tick is equal expected value
            assertEq(secondPositionsInTick, 0, "wrong secondPositionsInTick");
            // second max initialized tick
            int24 secondMaxInitializedTick = protocol.maxInitializedTick();
            // check if second max initialized is equal expected value
            assertEq(secondMaxInitializedTick, 74_600, "wrong secondMaxInitializedTick");
            // second total long positions
            uint256 secondTotalLongPositions = protocol.totalLongPositions();
            // check if second total long positions is equal expected value
            assertEq(secondTotalLongPositions, 7, "wrong secondTotalLongPositions");
        }
    }

    /* @custom:scenario Simulate user open positions.
     * @custom:when Block number increase 20, simulate a -20% 
     * asset price drawdown and liquidate action 
     * should execute liquidation.
     * @custom:then Tick version should be incremented.
     */
    function test_openLiquidatorLiquidation() public {
        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(true, protocol.getUsers(protocol.userCount()));
        // first mock init open position
        uint256 firstTickVersion = protocol.tickVersion(initialTick);
        assertEq(firstTickVersion, 0, "wrong firstTickVersion");
        // first total expo
        uint256 firstTotalExpo = protocol.totalExpo();
        // check if first total expo match initial value
        assertEq(firstTotalExpo, 1_203_282_859_929_999_999_016, "wrong firstTotalExpo");
        // first tick hash
        bytes32 firstTickHash = protocol.tickHash(initialTick);
        // check if first tick hash match initial value
        assertEq(
            firstTickHash,
            bytes32(
                uint256(
                    31_303_468_123_476_320_952_309_786_101_268_354_098_456_914_902_927_505_641_948_359_107_244_083_539_650
                )
            ),
            "wrong firstTickHash"
        );
        // first total expo by tick
        uint256 firstTotalExpoByTick = protocol.totalExpoByTick(initialTick);
        // check if first total expo by tick match initial value
        assertEq(firstTotalExpoByTick, 1_183_442_919_400_000_000_000, "wrong firstTotalExpoByTick");
        // first long position length
        uint256 firstLongPositionsLengthByTick = protocol.longPositionsLength(initialTick);
        // check if first long position length match initial value
        assertEq(firstLongPositionsLengthByTick, 10, "wrong firstLongPositionsLengthByTick");
        // first position in tick
        uint256 firstPositionsInTick = protocol.positionsInTick(initialTick);
        // check if first position in tick match initial value
        assertEq(firstPositionsInTick, 10, "wrong firstPositionsInTick");
        // first max initialized tick
        int24 firstMaxInitializedTick = protocol.maxInitializedTick();
        // check if first max initialized match initial value
        assertEq(firstMaxInitializedTick, 76_900, "wrong firstMaxInitializedTick");
        // first total long positions
        uint256 firstTotalLongPositions = protocol.totalLongPositions();
        // check if first total long positions match initial value
        assertEq(firstTotalLongPositions, 12, "wrong firstTotalLongPositions");

        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + 20); // block number
        // get price info
        (, bytes memory priceData) = protocol.getPriceInfo(block.number);
        // liquidator liquidation
        protocol.liquidate(priceData, 9);

        // to avoid stack too deep
        {
            // second tick version
            uint256 secondTickVersion = protocol.tickVersion(initialTick);
            // check if second tick version is updated properly
            assertEq(secondTickVersion, 1, "wrong secondTickVersion");
            // second total expo
            uint256 secondTotalExpo = protocol.totalExpo();
            // check if second total expo is equal expected value
            assertEq(secondTotalExpo, 19_839_940_529_999_999_016, "wrong secondTotalExpo");
            // second tick hash
            bytes32 secondTickHash = protocol.tickHash(initialTick);
            // check if second tick hash is equal expected value
            assertEq(
                secondTickHash,
                bytes32(
                    uint256(
                        112_445_457_736_805_415_271_282_785_611_942_110_906_241_620_093_834_231_219_694_755_927_915_188_543_033
                    )
                ),
                "wrong secondTickHash"
            );
            // second total expo by tick
            uint256 secondTotalExpoByTick = protocol.totalExpoByTick(initialTick);
            // check if second total expo by tick is equal expected value
            assertEq(secondTotalExpoByTick, 0, "wrong secondTotalExpoByTick");
        }

        // to avoid stack too deep
        {
            // second long position length
            uint256 secondLongPositionsLengthByTick = protocol.longPositionsLength(initialTick);
            // check if second long position length is equal expected value
            assertEq(secondLongPositionsLengthByTick, 0, "wrong secondLongPositionsLengthByTick");
            // second position in tick
            uint256 secondPositionsInTick = protocol.positionsInTick(initialTick);
            // check if second position in tick is equal expected value
            assertEq(secondPositionsInTick, 0, "wrong secondPositionsInTick");
            // second max initialized tick
            int24 secondMaxInitializedTick = protocol.maxInitializedTick();
            // check if second max initialized is equal expected value
            assertEq(secondMaxInitializedTick, 69_000, "wrong secondMaxInitializedTick");
            // second total long positions
            uint256 secondTotalLongPositions = protocol.totalLongPositions();
            // check if second total long positions is equal expected value
            assertEq(secondTotalLongPositions, 2, "wrong secondTotalLongPositions");
        }
    }
}
