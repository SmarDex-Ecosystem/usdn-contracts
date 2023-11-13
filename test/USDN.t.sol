// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USDNTokenFixture, USER_1 } from "test/utils/Fixtures.sol";

contract TestUSDNProtected is USDNTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_mint() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
        assertEq(usdn.balanceOf(USER_1), 100 ether);
    }

    function test_mintWithMultiplier() public {
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        usdn.adjustMultiplier(2 ether);
        usdn.revokeRole(usdn.ADJUSTMENT_ROLE(), address(this));
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
        assertEq(usdn.balanceOf(USER_1), 100 ether);
        assertEq(usdn.sharesOf(USER_1), 50 ether);
    }
}
