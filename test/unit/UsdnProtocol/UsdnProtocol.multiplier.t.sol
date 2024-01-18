// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

contract TestUsdnProtocolMultiplier is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(
            SetUpParams({
                initialDeposit: 10 ether,
                initialLong: 5 ether,
                initialPrice: 2000 ether,
                initialTimestamp: 1_704_092_400
            })
        );
    }

    function test_initiatePosition() public {
        vm.deal(USER_1, 20_000 ether);
        wstETH.mint(USER_1, 10_000 ether);
        vm.deal(USER_2, 20_000 ether);
        wstETH.mint(USER_2, 10_000 ether);

        protocol.mockInitiateOpenPosition(true, USER_1, 4000 ether, 2_000_000_000, 500 ether);
        emit log_named_decimal_uint("multiplier", protocol.liquidationMultiplier(), 38);

        vm.warp(DEFAULT_PARAMS.initialTimestamp + 1 days);
        protocol.mockInitiateOpenPosition(true, USER_2, 4000 ether, 2_000_000_000, 500 ether);
        emit log_named_decimal_uint("multiplier", protocol.liquidationMultiplier(), 38);
    }
}
