// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `burnSharesFrom` function of `UsdnNoRebase`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnNoRebaseBurnSharesFrom is UsdnNoRebaseTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Burning from a user with allowance
     * @custom:given An approved amount of 50 USDN
     * @custom:when 50 USDN are burned from the user
     * @custom:then The `Transfer` event is emitted with the user as the sender, the 0 address as the recipient and
     * an amount of 50 ether
     * @custom:and The user's balance is decreased by 50 ether
     * @custom:and The allowance is decreased by 50 ether
     */
    function test_burnSharesFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 50 ether);
        usdn.burnSharesFrom(USER_1, 50 ether);

        assertEq(usdn.balanceOf(USER_1), 50 ether, "balance after burn");
        assertEq(usdn.allowance(USER_1, address(this)), 0, "allowance after burn");
    }

    /**
     * @custom:scenario Burning from a user with insufficient allowance
     * @custom:given An approved amount of 50 USDN
     * @custom:when 51 USDN are burned from the user
     * @custom:then The transaction reverts with the `ERC20InsufficientAllowance` error
     */
    function test_RevertWhen_burnSharesFromInsufficientAllowance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 50 ether, 51 ether)
        );
        usdn.burnSharesFrom(USER_1, 51 ether);
    }

    /**
     * @custom:scenario Burning from a user with insufficient balance
     * @custom:given An approved amount of max
     * @custom:when 150 USDN are burned from the user
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnSharesFromInsufficientBalance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 150 ether)
        );
        usdn.burnSharesFrom(USER_1, 150 ether);
    }
}
