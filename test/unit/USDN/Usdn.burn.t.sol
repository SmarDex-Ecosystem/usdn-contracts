// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/// Test the `burn` and `burnFrom` functions.
contract TestUsdnBurn is UsdnTokenFixture {
    /// User starts with 100 tokens balance (multiplier is 1)
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /// Check that burning a portion of the balance results in the correct event and changes in supply and balances.
    function test_burnPartial() public {
        usdn.adjustMultiplier(1.1 ether);
        assertEq(usdn.balanceOf(USER_1), 110 ether);
        assertEq(usdn.sharesOf(USER_1), 100 ether);

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(USER_1, address(0), 10 ether); // expected event
        vm.prank(USER_1);
        usdn.burn(10 ether);

        assertEq(usdn.balanceOf(USER_1), 100 ether);
        assertEq(usdn.sharesOf(USER_1), 90_909_090_909_090_909_091);
        assertEq(usdn.totalSupply(), 100 ether);
        assertEq(usdn.totalShares(), 90_909_090_909_090_909_091);
    }

    /// Check that burning the entire balance results in the correct event and changes in supply and balances.
    function test_burnAll() public {
        usdn.adjustMultiplier(1.1 ether);
        assertEq(usdn.balanceOf(USER_1), 110 ether);
        assertEq(usdn.sharesOf(USER_1), 100 ether);

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(USER_1, address(0), 110 ether); // expected event
        vm.prank(USER_1);
        usdn.burn(110 ether);

        assertEq(usdn.balanceOf(USER_1), 0);
        assertEq(usdn.sharesOf(USER_1), 0);
        assertEq(usdn.totalSupply(), 0);
        assertEq(usdn.totalShares(), 0);
    }

    /// Check that burning an amount larger than the balance reverts.
    function test_RevertWhen_burnInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 101 ether)
        );
        vm.prank(USER_1);
        usdn.burn(101 ether);
    }

    /// Check that burning an amount larger than the balance reverts (when multiplier > 1).
    function test_RevertWhen_burnInsufficientBalanceWithMultiplier() public {
        usdn.adjustMultiplier(2 ether);
        assertEq(usdn.balanceOf(USER_1), 200 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 200 ether, 201 ether)
        );
        vm.prank(USER_1);
        usdn.burn(201 ether);
    }

    /// Check that burning from a user results in the correct event and changes in supply and balances.
    function test_burnFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        usdn.adjustMultiplier(2 ether);
        assertEq(usdn.allowance(USER_1, address(this)), 50 ether); // changing multiplier doesn't affect allowance

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(USER_1, address(0), 50 ether); // expected event
        usdn.burnFrom(USER_1, 50 ether);
    }

    /// Check that burning from a user more than the allowance reverts.
    function test_RevertWhen_burnFromInsufficientAllowance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 50 ether, 51 ether)
        );
        usdn.burnFrom(USER_1, 51 ether);
    }

    /// Check that burning from a user more than their balance reverts.
    function test_RevertWhen_burnFromInsufficientBalance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 150 ether)
        );
        usdn.burnFrom(USER_1, 150 ether);
    }
}
