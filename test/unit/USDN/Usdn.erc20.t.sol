// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/// Test ERC-20 functions.
contract TestUsdnErc20 is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    function test_name() public {
        assertEq(usdn.name(), "Ultimate Synthetic Delta Neutral");
    }

    function test_symbol() public {
        assertEq(usdn.symbol(), "USDN");
    }

    function test_approve() public {
        vm.expectEmit(true, true, true, false, address(usdn));
        emit Approval(USER_1, address(this), 50 ether); // expected event
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        assertEq(usdn.allowance(USER_1, address(this)), 50 ether);
    }

    function test_RevertWhen_approveZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(USER_1);
        usdn.approve(address(0), 50 ether);
    }

    function test_transfer() public {
        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(USER_1, address(this), 50 ether); // expected event
        vm.prank(USER_1);
        usdn.transfer(address(this), 50 ether);

        assertEq(usdn.balanceOf(USER_1), 50 ether);
        assertEq(usdn.balanceOf(address(this)), 50 ether);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(USER_1);
        usdn.transfer(address(0), 50 ether);
    }

    function test_transferFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(USER_1, address(this), 50 ether); // expected event
        usdn.transferFrom(USER_1, address(this), 50 ether);

        assertEq(usdn.balanceOf(USER_1), 50 ether);
        assertEq(usdn.balanceOf(address(this)), 50 ether);
    }

    function test_RevertWhen_transferFromToZeroAddress() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.transferFrom(USER_1, address(0), 50 ether);
    }
}
