// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

contract TestUsdnProtocolMultiplier is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_initiatePosition() public {
        vm.deal(USER_1, 20_000 ether);
        wstETH.mint(USER_1, 10_000 ether);
        vm.prank(USER_1);
        wstETH.approve(address(protocol), type(uint256).max);

        protocol.mockInitiateOpenPosition(true, USER_1, 1900 ether, 1_100_000_000, 100 ether);
    }
}
