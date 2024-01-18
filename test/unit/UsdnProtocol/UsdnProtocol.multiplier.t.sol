// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

contract TestUsdnProtocolMultiplier is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_initiatePosition() public {
        createAndFundUser(address(wstETH), 10_000 ether, USER_1);
        emit log_named_decimal_uint("safety margin", protocol._maxLiquidationPriceWithSafetyMargin(2000 ether), 18);
        // protocol.mockInitiateOpenPosition(false, USER_1, 2000 ether, 1_100_000_000, 1 ether);
    }
}
