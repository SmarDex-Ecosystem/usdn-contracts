// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

contract TestUsdnProtocolMultiplier is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    function test_initiatePosition() public {
        vm.deal(USER_1, 20_000 ether);
        wstETH.mint(USER_1, 10_000 ether);
        vm.prank(USER_1);
        wstETH.approve(address(protocol), type(uint256).max);
        vm.deal(USER_2, 20_000 ether);
        wstETH.mint(USER_2, 10_000 ether);
        vm.prank(USER_2);
        wstETH.approve(address(protocol), type(uint256).max);
        vm.deal(USER_3, 20_000 ether);
        wstETH.mint(USER_3, 10_000 ether);
        vm.prank(USER_3);
        wstETH.approve(address(protocol), type(uint256).max);

        protocol.mockInitiateOpenPosition(true, USER_1, 2000 ether, 2_000_000_000, 500 ether);
    }
}
