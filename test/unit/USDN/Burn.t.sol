// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `burn` function of `USDN`
 * @custom:background Given a user with 100 tokens
 * @custom:and The contract has the `MINTER_ROLE` and `REBASER_ROLE`
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnBurn is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Burning a portion of the balance
     * @custom:given A divisor of 0.5x MAX_DIVISOR
     * @custom:and A user with 200 USDN
     * @custom:when 50 USDN are burned
     * @custom:then The `Transfer` event is emitted with the user as the sender, the zero address as the recipient and
     * amount 50
     * @custom:and The user's balance is decreased by 50
     * @custom:and The user's shares are decreased by 25
     * @custom:and The total supply is decreased by 50
     * @custom:and The total shares are decreased by 25
     */
    function test_burnPartial() public {
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        assertEq(usdn.balanceOf(USER_1), 200 ether, "initial balance");
        assertEq(usdn.sharesOf(USER_1), 100 ether * usdn.MAX_DIVISOR(), "initial shares");

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 50 ether); // expected event
        vm.prank(USER_1);
        usdn.burn(50 ether);

        assertEq(usdn.balanceOf(USER_1), 150 ether, "balance after burn");
        assertEq(usdn.sharesOf(USER_1), 75 ether * usdn.MAX_DIVISOR(), "shares after burn");
        assertEq(usdn.totalSupply(), 150 ether, "total supply after burn");
        assertEq(usdn.totalShares(), 75 ether * usdn.MAX_DIVISOR(), "total shares after burn");
    }

    /**
     * @custom:scenario Burning the entire balance
     * @custom:given A divisor of 0.9x MAX_DIVISOR
     * @custom:and A user with 111.1 USDN
     * @custom:when 111.1 USDN are burned
     * @custom:then The `Transfer` event is emitted with the user as the sender, the zero address as the recipient and
     * amount 111.1
     * @custom:and The user's balance is zero
     * @custom:and The total supply is zero
     * @dev It's possible that there are remaining shares in the user balance and total supply, but they represent less
     * than 1 USDN at the current divisor. This means that the user might not be able to burn the full balance of their
     * tokens, they might have a fraction of a token left.
     */
    function test_burnAll() public {
        usdn.rebase(9 * usdn.MAX_DIVISOR() / 10);
        assertEq(usdn.balanceOf(USER_1), 111_111_111_111_111_111_111, "initial balance");
        assertEq(usdn.sharesOf(USER_1), 100 ether * usdn.MAX_DIVISOR(), "initial shares");

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 111_111_111_111_111_111_111); // expected event
        vm.prank(USER_1);
        usdn.burn(111_111_111_111_111_111_111);

        assertEq(usdn.balanceOf(USER_1), 0, "balance after burn");
        assertEq(usdn.totalSupply(), 0, "total supply after burn");
    }

    /**
     * @custom:scenario Burning more than the balance
     * @custom:when 101 USDN are burned
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 101 ether)
        );
        vm.prank(USER_1);
        usdn.burn(101 ether);
    }

    /**
     * @custom:scenario Burning more than the balance
     * @custom:given A divisor of 0.5x MAX_DIVISOR
     * @custom:and A user with 200 USDN
     * @custom:when 201 USDN are burned
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnInsufficientBalanceWithMultiplier() public {
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        assertEq(usdn.balanceOf(USER_1), 200 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 200 ether, 201 ether)
        );
        vm.prank(USER_1);
        usdn.burn(201 ether);
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

    /**
     * @custom:scenario Burning from the zero address
     * @custom:when 50 USDN are burned from the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidSender` error
     * @dev This function is not available in the USDN contract, only in the test handler
     */
    function test_RevertWhen_burnFromZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        usdn.burn(address(0), 50 ether);
    }
}
