// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

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
        int24 initialTick = mockInitiateOpenPosition(20 ether, true, getUsers(users.length));
        assertEq(protocol.tickVersion(initialTick), 0, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 1158.732152064999999016 ether, "wrong first totalExpo");
        // check if first tick hash match initial value
        assertEq(
            protocol.tickHash(initialTick),
            0xbce35594a2837f2c23ed3cc1e16e9aababe85ea74c961a9640b9df6a41acfdf6,
            "wrong first tickHash"
        );
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 1148.8121818 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_100, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint8 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);

        // second mock init open position
        mockInitiateOpenPosition(20 ether, true, getUsers(users.length / 2));

        uint256 secondTickVersion = protocol.tickVersion(initialTick);
        // check if second tick version is updated properly
        assertEq(secondTickVersion, 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 608.029718304999999016 ether, "wrong second totalExpo");
        // check if second tick hash is equal expected value
        assertEq(
            protocol.tickHash(initialTick),
            0xa4eef8a4a485dd8bc77ecca33dc25b1d2f1f1f9a156c5087e94d27978b5f462a,
            "wrong second tickHash"
        );
        // check if second total expo by tick is equal expected value
        assertEq(protocol.totalExpoByTick(initialTick), 0, "wrong second totalExpoByTick");
        // check if second long position length is equal expected value
        assertEq(protocol.longPositionsLength(initialTick), 0, "wrong second longPositionsLength");
        // check if second position in tick is equal expected value
        assertEq(protocol.positionsInTick(initialTick), 0, "wrong second positionsInTick");
        // check if second max initialized is equal expected value
        assertEq(protocol.maxInitializedTick(), 71_900, "wrong second maxInitializedTick");
        // check if second total long positions is equal expected value
        assertEq(protocol.totalLongPositions(), 7, "wrong second totalLongPositions");
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
        int24 initialTick = mockInitiateOpenPosition(20 ether, true, getUsers(users.length));
        assertEq(protocol.tickVersion(initialTick), 0, "wrong first tickVersion");
        // check if first total expo match initial value
        assertEq(protocol.totalExpo(), 1158.732152064999999016 ether, "wrong first totalExpo");
        // check if first tick hash match initial value
        assertEq(
            protocol.tickHash(initialTick),
            0xbce35594a2837f2c23ed3cc1e16e9aababe85ea74c961a9640b9df6a41acfdf6,
            "wrong first tickHash"
        );
        // check if first total expo by tick match initial value
        assertEq(protocol.totalExpoByTick(initialTick), 1148.8121818 ether, "wrong first totalExpoByTick");
        // check if first long position length match initial value
        assertEq(protocol.longPositionsLength(initialTick), 10, "wrong first longPositionsLength");
        // check if first position in tick match initial value
        assertEq(protocol.positionsInTick(initialTick), 10, "wrong first positionsInTick");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_100, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint8 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);
        // get price info
        (, bytes memory priceData) = getPriceInfo(block.number);
        // liquidator liquidation
        protocol.liquidate(priceData, 9);

        // check if second tick version is updated properly
        assertEq(protocol.tickVersion(initialTick), 1, "wrong second tickVersion");
        // check if second total expo is equal expected value
        assertEq(protocol.totalExpo(), 9.919970264999999016 ether, "wrong second totalExpo");
        // check if second tick hash is equal expected value
        assertEq(
            protocol.tickHash(initialTick),
            0xa4eef8a4a485dd8bc77ecca33dc25b1d2f1f1f9a156c5087e94d27978b5f462a,
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
        // user count
        uint256 length = allUsers.length;
        // sorted user array
        address[][] memory splitUsers = new address[][](length);
        // user splitted in many unique user array
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
            initialTicks[i] = mockInitiateOpenPosition(20 ether, true, splitUsers[i]);
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
        assertEq(protocol.totalExpo(), 1172.602317304999999016 ether, "wrong first totalExpo");
        // check if first max initialized match initial value
        assertEq(protocol.maxInitializedTick(), 74_100, "wrong first maxInitializedTick");
        // check if first total long positions match initial value
        assertEq(protocol.totalLongPositions(), 12, "wrong first totalLongPositions");

        uint16 blockDiff = 20;
        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + blockDiff); // block number
        // increment timestamp equivalent required by pnl
        vm.warp(block.timestamp + blockDiff * 12);
        // get price info
        (, bytes memory priceData) = getPriceInfo(block.number);

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
        assertEq(protocol.totalExpo(), 596.195268324999999016 ether, "wrong second totalExpo");
        // check if second max initialized match expected value
        assertEq(protocol.maxInitializedTick(), 73_600, "wrong second maxInitializedTick");
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
        assertEq(protocol.totalExpo(), 9.919970264999999016 ether, "wrong second totalExpo");
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
        int24 initialTick = mockInitiateOpenPosition(20 ether, true, getUsers(users.length));
        // max liquidation iteration constant
        uint16 maxLiquidationIteration = protocol.maxLiquidationIteration();
        // check if first tick version match initial value
        assertEq(protocol.tickVersion(initialTick), 0, "wrong first tickVersion");

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
}
