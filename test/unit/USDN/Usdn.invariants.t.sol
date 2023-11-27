// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

contract TestUsdnInvariants is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();

        targetContract(address(usdn));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = usdn.adjustDivisorTest.selector;
        selectors[1] = usdn.mintTest.selector;
        selectors[2] = usdn.burnTest.selector;
        selectors[3] = usdn.transferTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: selectors }));
    }

    function invariant_balances() public {
        assertEq(usdn.balances(USER_1), usdn.balanceOf(USER_1));
        assertEq(usdn.balances(USER_2), usdn.balanceOf(USER_2));
        assertEq(usdn.balances(USER_3), usdn.balanceOf(USER_3));
        assertEq(usdn.balances(USER_4), usdn.balanceOf(USER_4));
    }

    function invariant_totalSupply() public {
        assertEq(usdn.totalSupply(), usdn.totalSupplySum());
    }
}
