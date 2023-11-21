// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/Test.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The `convertToShares` function of `USDN`
 */
contract TestUsdnConvertToShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_RevertWhen_tokenAmountOverflows() public {
        vm.expectRevert(abi.encodeWithSelector(UsdnMaxTokensExceeded.selector, type(uint256).max));
        usdn.convertToShares(type(uint256).max);
    }
}
