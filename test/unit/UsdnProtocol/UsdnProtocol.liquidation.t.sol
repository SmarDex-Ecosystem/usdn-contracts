// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    function test_open_user_liquidation() public {
        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(true, protocol.getUsers(protocol.userCount()));
        // first mock init open position
        uint256 firstTickVersion = protocol.tickVersion(initialTick);
        // first total expo
        uint256 firstTotalExpo = protocol.totalExpo();
        // check if first total expo greater than zero
        assertEq(firstTotalExpo != 0, true);
        // first tick hash
        bytes32 firstTickHash = protocol.tickHash(initialTick);
        // check if first tick hash is well fetched
        assertEq(firstTickHash != bytes32(""), true);
        // first total expo by tick
        uint256 firstTotalExpoByTick = protocol.totalExpoByTick(initialTick);
        // check if first total expo by tick is greater than zero
        assertEq(firstTotalExpoByTick != 0, true);
        // first long position length
        uint256 firstLongPositionsLength = protocol.longPositionsLength(initialTick);
        // check if first long position length is greater than zero
        assertEq(firstLongPositionsLength != 0, true);
        // first position in tick
        uint256 firstPositionsInTick = protocol.positionsInTick(initialTick);
        // check if first position in tick is greater than zero
        assertEq(firstPositionsInTick != 0, true);
        // first max initialized tick
        int24 firstMaxInitializedTick = protocol.maxInitializedTick();
        // check if first max initialized is greater than zero
        assertEq(firstMaxInitializedTick != 0, true);
        // first total long positions
        uint256 firstTotalLongPositions = protocol.totalLongPositions();
        // check if first total long positions is greater than zero
        assertEq(firstTotalLongPositions != 0, true);

        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + 20); // block number
        // second mock init open position
        protocol.mockInitiateOpenPosition(true, protocol.getUsers(protocol.userCount() / 2));

        // second tick version
        uint256 secondTickVersion = protocol.tickVersion(initialTick);
        // check if first tick version is different than second
        assertEq(firstTickVersion != secondTickVersion, true);
        // second total expo
        uint256 secondTotalExpo = protocol.totalExpo();
        // check if first total expo is different than second
        assertEq(firstTotalExpo != secondTotalExpo, true);
        // second tick hash
        bytes32 secondTickHash = protocol.tickHash(initialTick);
        // check if first tick hash is different than second
        assertEq(firstTickHash != secondTickHash, true);
        // second total expo by tick
        uint256 secondTotalExpoByTick = protocol.totalExpoByTick(initialTick);
        // check if first total expo by tick is different than second
        assertEq(firstTotalExpoByTick != secondTotalExpoByTick, true);
        // second long position length
        uint256 secondLongPositionsLength = protocol.longPositionsLength(initialTick);
        // check if first long position length is is different than second
        assertEq(firstLongPositionsLength != secondLongPositionsLength, true);
        // second position in tick
        uint256 secondPositionsInTick = protocol.positionsInTick(initialTick);
        // check if first position in tick is is different than second
        assertEq(firstPositionsInTick != secondPositionsInTick, true);
        // second max initialized tick
        int24 secondMaxInitializedTick = protocol.maxInitializedTick();
        // check if first max initialized is is different than second
        assertEq(firstMaxInitializedTick != secondMaxInitializedTick, true);
        // second total long positions
        uint256 secondTotalLongPositions = protocol.totalLongPositions();
        // check if first total long positions is is different than second
        assertEq(firstTotalLongPositions != secondTotalLongPositions, true);
    }

    /* @custom:scenario Simulate user open positions.
     * @custom:when Block number increase 20, simulate a -20% 
     * asset price drawdown and liquidate action 
     * should execute liquidation.
     * @custom:then Tick version should be incremented.
     */
    function test_open_liquidator_liquidation() public {
        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(true, protocol.getUsers(protocol.userCount()));
        // first mock init open position
        uint256 firstTickVersion = protocol.tickVersion(initialTick);
        // first total expo
        uint256 firstTotalExpo = protocol.totalExpo();
        // check if first total expo greater than zero
        assertEq(firstTotalExpo != 0, true);
        // first tick hash
        bytes32 firstTickHash = protocol.tickHash(initialTick);
        // check if first tick hash is well fetched
        assertEq(firstTickHash != bytes32(""), true);
        // first total expo by tick
        uint256 firstTotalExpoByTick = protocol.totalExpoByTick(initialTick);
        // check if first total expo by tick is greater than zero
        assertEq(firstTotalExpoByTick != 0, true);
        // first long position length
        uint256 firstLongPositionsLength = protocol.longPositionsLength(initialTick);
        // check if first long position length is greater than zero
        assertEq(firstLongPositionsLength != 0, true);
        // first position in tick
        uint256 firstPositionsInTick = protocol.positionsInTick(initialTick);
        // check if first position in tick is greater than zero
        assertEq(firstPositionsInTick != 0, true);
        // first max initialized tick
        int24 firstMaxInitializedTick = protocol.maxInitializedTick();
        // check if first max initialized is greater than zero
        assertEq(firstMaxInitializedTick != 0, true);
        // first total long positions
        uint256 firstTotalLongPositions = protocol.totalLongPositions();
        // check if first total long positions is greater than zero
        assertEq(firstTotalLongPositions != 0, true);

        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + 20); // block number
        // get price info
        (, bytes memory priceData) = protocol.getPriceInfo(block.number);
        // liquidator liquidation
        protocol.liquidate(priceData, 9);

        // second tick version
        uint256 secondTickVersion = protocol.tickVersion(initialTick);
        // check if first tick version is different than second
        assertEq(firstTickVersion != secondTickVersion, true);
        // second total expo
        uint256 secondTotalExpo = protocol.totalExpo();
        // check if first total expo is different than second
        assertEq(firstTotalExpo != secondTotalExpo, true);
        // second tick hash
        bytes32 secondTickHash = protocol.tickHash(initialTick);
        // check if first tick hash is different than second
        assertEq(firstTickHash != secondTickHash, true);
        // second total expo by tick
        uint256 secondTotalExpoByTick = protocol.totalExpoByTick(initialTick);
        // check if first total expo by tick is different than second
        assertEq(firstTotalExpoByTick != secondTotalExpoByTick, true);
        // second long position length
        uint256 secondLongPositionsLength = protocol.longPositionsLength(initialTick);
        // check if first long position length is is different than second
        assertEq(firstLongPositionsLength != secondLongPositionsLength, true);
        // second position in tick
        uint256 secondPositionsInTick = protocol.positionsInTick(initialTick);
        // check if first position in tick is is different than second
        assertEq(firstPositionsInTick != secondPositionsInTick, true);
        // second max initialized tick
        int24 secondMaxInitializedTick = protocol.maxInitializedTick();
        // check if first max initialized is is different than second
        assertEq(firstMaxInitializedTick != secondMaxInitializedTick, true);
        // second total long positions
        uint256 secondTotalLongPositions = protocol.totalLongPositions();
        // check if first total long positions is is different than second
        assertEq(firstTotalLongPositions != secondTotalLongPositions, true);
    }
}
