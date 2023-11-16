// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/// Test ERC-20 functions.
contract TestUsdnErc20 is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_name() public {
        assertEq(usdn.name(), "Ultimate Synthetic Delta Neutral");
    }

    function test_symbol() public {
        assertEq(usdn.symbol(), "USDN");
    }
}
