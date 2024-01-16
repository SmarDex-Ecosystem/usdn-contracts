// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    // simulate open position and drawdown 20%
    // liquidations by any protocol action
    function test_open_user_liquidation() public {
        uint256 refAmount = 20 ether;

        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(refAmount, true, protocol.getUsers());

        // first mock init open position
        uint256 firstTickVersion = protocol.tickVersion(initialTick);

        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + 20); // block number

        // second mock init open position
        protocol.mockInitiateOpenPosition(refAmount, true, protocol.getUsers());

        uint256 secondTickVersion = protocol.tickVersion(initialTick);

        // check if tick version is well updated after liquidation
        assertEq(firstTickVersion == secondTickVersion, false);

        protocol.setPrevActionBlock(block.number);
    }

    // simulate open position and drawdown 20%
    // liquidations by liquidation protocol action
    function test_open_liquidator_liquidation() public {
        uint256 refAmount = 20 ether;

        // mock initiate open
        int24 initialTick = protocol.mockInitiateOpenPosition(refAmount, true, protocol.getUsers());

        // first mock init open position
        uint256 firstTickVersion = protocol.tickVersion(initialTick);

        // increment 20 block (20% drawdown)
        // to reach liquidation price
        vm.roll(block.number + 20); // block number

        (, bytes memory priceData) = protocol.getPriceInfo(block.number);

        // liquidator liquidation
        protocol.liquidate(priceData, 9);

        uint256 secondTickVersion = protocol.tickVersion(initialTick);

        // check if tick version is well updated after liquidation
        assertEq(firstTickVersion == secondTickVersion, false);

        protocol.setPrevActionBlock(block.number);
    }
}
