// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USDNTokenFixture, USER_1 } from "test/utils/Fixtures.sol";

contract TestUSDNMint is USDNTokenFixture {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public override {
        super.setUp();
    }

    function test_mint() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.mint(USER_1, 100 ether);
        assertEq(usdn.balanceOf(USER_1), 100 ether);
    }

    function test_mintWithMultiplier() public {
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        usdn.adjustMultiplier(2 ether);
        usdn.revokeRole(usdn.ADJUSTMENT_ROLE(), address(this));
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.mint(USER_1, 100 ether);
        assertEq(usdn.balanceOf(USER_1), 100 ether);
        assertEq(usdn.sharesOf(USER_1), 50 ether);
    }

    function test_mintGuards() public {
        // Missing role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.MINTER_ROLE()
            )
        );
        usdn.mint(USER_1, 100 ether);

        // Mint to zero address
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.mint(address(0), 100 ether);
    }
}

contract TestUSDNAdjust is USDNTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_adjustMultiplier() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        vm.expectEmit(true, true, false, false, address(usdn));
        emit MultiplierAdjusted(1 ether, 1 ether + 1); // expected event
        usdn.adjustMultiplier(1 ether + 1);
        assertEq(usdn.sharesOf(USER_1), 100 ether);
        assertEq(usdn.balanceOf(USER_1), 100 ether + 100);
    }

    function test_adjustMultiplierGuards() public {
        // Missing role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.ADJUSTMENT_ROLE()
            )
        );
        usdn.adjustMultiplier(2 ether);

        // Invalid multiplier
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        vm.expectRevert(abi.encodeWithSelector(InvalidMultiplier.selector, 1 ether));
        usdn.adjustMultiplier(1 ether);
        vm.expectRevert(abi.encodeWithSelector(InvalidMultiplier.selector, 0.5 ether));
        usdn.adjustMultiplier(0.5 ether);
    }
}

contract TestUSDNBurn is USDNTokenFixture {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    function test_burn() public {
        usdn.adjustMultiplier(1.1 ether);
        assertEq(usdn.balanceOf(USER_1), 110 ether);
        assertEq(usdn.sharesOf(USER_1), 100 ether);

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(USER_1, address(0), 100 ether); // expected event
        vm.startPrank(USER_1);
        usdn.burn(10 ether);
        assertEq(usdn.balanceOf(USER_1), 100 ether);
        assertEq(usdn.sharesOf(USER_1), 90_909_090_909_090_909_091);

        usdn.burn(100 ether);
        assertEq(usdn.balanceOf(USER_1), 0);
        assertEq(usdn.sharesOf(USER_1), 0);
        vm.stopPrank();
    }

    function test_burnGuards() public {
        // Amount too large
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 101 ether)
        );
        vm.prank(USER_1);
        usdn.burn(101 ether);

        usdn.adjustMultiplier(2 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 200 ether, 201 ether)
        );
        vm.prank(USER_1);
        usdn.burn(201 ether);
    }

    function test_burnFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        usdn.adjustMultiplier(2 ether);
        assertEq(usdn.allowance(USER_1, address(this)), 50 ether);

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(USER_1, address(0), 50 ether); // expected event
        usdn.burnFrom(USER_1, 50 ether);
    }

    function test_burnFromGuards() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 50 ether, 51 ether)
        );
        usdn.burnFrom(USER_1, 51 ether);

        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 150 ether)
        );
        usdn.burnFrom(USER_1, 150 ether);
    }
}
