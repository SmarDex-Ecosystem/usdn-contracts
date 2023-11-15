// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

contract TestUsdnMint is UsdnTokenFixture {
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

    function test_RevertWhen_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.MINTER_ROLE()
            )
        );
        usdn.mint(USER_1, 100 ether);
    }

    function test_RevertWhen_mintToZeroAddress() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.mint(address(0), 100 ether);
    }
}
