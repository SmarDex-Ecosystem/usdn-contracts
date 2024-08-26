// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The ERC-20 functions of `USDN`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnErc20 is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Retrieving the name
     * @custom:when The name is retrieved
     * @custom:then The name is equal to "Ultimate Synthetic Delta Neutral"
     */
    function test_name() public view {
        assertEq(usdn.name(), "Ultimate Synthetic Delta Neutral");
    }

    /**
     * @custom:scenario Retrieving the symbol
     * @custom:when The symbol is retrieved
     * @custom:then The symbol is equal to "USDN"
     */
    function test_symbol() public view {
        assertEq(usdn.symbol(), "USDN");
    }

    /**
     * @custom:scenario Retrieving the decimals
     * @custom:when The decimals are retrieved
     * @custom:then The decimals are equal to 18
     */
    function test_decimals() public view {
        assertEq(usdn.decimals(), 18);
    }

    /**
     * @custom:scenario Approving a spender
     * @custom:when The spender is approved to spend 50 tokens
     * @custom:then The `Approval` event is emitted with the user as the owner, this contract as the spender and amount
     * 50 tokens
     * @custom:and The allowance of the user for this contract is 50 tokens
     */
    function test_approve() public {
        vm.expectEmit(address(usdn));
        emit Approval(USER_1, address(this), 50 ether); // expected event
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        assertEq(usdn.allowance(USER_1, address(this)), 50 ether);
    }

    /**
     * @custom:scenario Approving the zero address
     * @custom:when The zero address is approved to spend 50 tokens
     * @custom:then The transaction reverts with the `ERC20InvalidSpender` error
     */
    function test_RevertWhen_approveZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(USER_1);
        usdn.approve(address(0), 50 ether);
    }

    /**
     * @custom:scenario Approving with zero address as the owner
     * @custom:when The zero address account wants to approve another address
     * @custom:then The transaction reverts with the `ERC20InvalidApprover` error
     * @dev This function is not available in the USDN contract, only in the test handler
     */
    function test_RevertWhen_approveFromZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        usdn.i_approve(address(0), USER_1, 50 ether);
    }

    /**
     * @custom:scenario Transferring tokens
     * @custom:when 50 tokens are transferred to this contract
     * @custom:then The `Transfer` event is emitted with the user as the sender, this contract as the recipient and
     * amount 50
     * @custom:and The user's balance is decreased by 50
     * @custom:and This contract's balance is increased by 50
     */
    function test_transfer() public {
        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(this), 50 ether); // expected event
        vm.prank(USER_1);
        usdn.transfer(address(this), 50 ether);

        assertEq(usdn.balanceOf(USER_1), 50 ether, "balance of user");
        assertEq(usdn.balanceOf(address(this)), 50 ether, "balance of contract");
    }

    /**
     * @custom:scenario Transferring tokens to the zero address
     * @custom:when 50 tokens are transferred to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(USER_1);
        usdn.transfer(address(0), 50 ether);
    }

    /**
     * @custom:scenario Transferring tokens from the zero address
     * @custom:when 50 tokens are transferred from the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidSender` error
     * @dev This function is not available in the USDN contract, only in the test handler
     */
    function test_RevertWhen_transferFromZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        usdn.i_transfer(address(0), USER_1, 50 ether);
    }

    /**
     * @custom:scenario Transferring tokens from a user with allowance
     * @custom:given An approved amount of 50 tokens
     * @custom:when 50 tokens are transferred from the user to this contract
     * @custom:then The `Transfer` event is emitted with the user as the sender, this contract as the recipient and
     * amount 50
     * @custom:and The user's balance is decreased by 50
     * @custom:and This contract's balance is increased by 50
     */
    function test_transferFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(this), 50 ether); // expected event
        usdn.transferFrom(USER_1, address(this), 50 ether);

        assertEq(usdn.balanceOf(USER_1), 50 ether, "balance of user");
        assertEq(usdn.balanceOf(address(this)), 50 ether, "balance of contract");
    }

    /**
     * @custom:scenario Transferring tokens from a user with allowance to the zero address
     * @custom:given An approved amount of 50 tokens
     * @custom:when 50 tokens are transferred from the user to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_transferFromToZeroAddress() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.transferFrom(USER_1, address(0), 50 ether);
    }
}
