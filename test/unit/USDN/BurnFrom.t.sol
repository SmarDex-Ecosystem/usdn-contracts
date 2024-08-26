// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `burnFrom` function of `USDN`
 * @custom:background Given a user with 100 tokens
 * @custom:and The contract has the `MINTER_ROLE` and `REBASER_ROLE`
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnBurnFrom is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Burning from a user with allowance
     * @custom:given An approved amount of 50 USDN
     * @custom:and A divisor of 0.5x MAX_DIVISOR
     * @custom:and A user with 200 USDN
     * @custom:when 50 USDN are burned from the user
     * @custom:then The `Transfer` event is emitted with the user as the sender, this contract as the recipient and
     * amount 50
     * @custom:and The user's balance is decreased by 50
     * @custom:and The allowance is decreased by 50
     */
    function test_burnFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        // changing multiplier doesn't affect allowance
        assertEq(usdn.allowance(USER_1, address(this)), 50 ether, "initial allowance");

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 50 ether); // expected event
        usdn.burnFrom(USER_1, 50 ether);

        assertEq(usdn.balanceOf(USER_1), 150 ether, "balance after burn");
        assertEq(usdn.allowance(USER_1, address(this)), 0, "allowance after burn");
    }

    /**
     * @custom:scenario Burning from a user with insufficient allowance
     * @custom:given An approved amount of 50 USDN
     * @custom:when 51 USDN are burned from the user
     * @custom:then The transaction reverts with the `ERC20InsufficientAllowance` error
     */
    function test_RevertWhen_burnFromInsufficientAllowance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 50 ether, 51 ether)
        );
        usdn.burnFrom(USER_1, 51 ether);
    }

    /**
     * @custom:scenario Burning from a user with insufficient balance
     * @custom:given An approved amount of max
     * @custom:when 150 USDN are burned from the user
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnFromInsufficientBalance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 150 ether)
        );
        usdn.burnFrom(USER_1, 150 ether);
    }
}
