// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `TestUsdnBurnSharesFrom` function of `USDN`
 * @custom:background Given a user with 100e36 shares
 * @custom:and The contract has the `MINTER_ROLE` and `REBASER_ROLE`
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnBurnSharesFrom is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mintShares(USER_1, 100e36);
    }

    /**
     * @custom:scenario Burning shares from a user with allowance
     * @custom:given An approved amount of 100 USDN
     * @custom:and A divisor of 0.5x MAX_DIVISOR
     * @custom:and A user with 200 USDN or 100e36 shares
     * @custom:when 50e36 shares are burned from the user
     * @custom:then The `Transfer` event is emitted with the user as the sender, this contract as the recipient and
     * amount 100 tokens
     * @custom:and The user's shares balance is decreased by 50e36
     * @custom:and The user's balance is decreased by 100 tokens
     * @custom:and The allowance is decreased by 100 tokens
     */
    function test_burnSharesFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 100 ether);

        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        // changing multiplier doesn't affect allowance
        assertEq(usdn.allowance(USER_1, address(this)), 100 ether, "initial allowance");

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 100 ether); // expected event
        usdn.burnSharesFrom(USER_1, 50e36);

        assertEq(usdn.sharesOf(USER_1), 50e36, "shares balance after burn");
        assertEq(usdn.balanceOf(USER_1), 100 ether, "tokens balance after burn");
        assertEq(usdn.allowance(USER_1, address(this)), 0, "allowance after burn");
    }

    /**
     * @custom:scenario Burning shares from a user with insufficient allowance
     * @custom:given An approved amount of 50 USDN
     * @custom:when 51e36 shares are burned from the user
     * @custom:then The transaction reverts with the `ERC20InsufficientAllowance` error
     */
    function test_RevertWhen_burnSharesFromInsufficientAllowance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 50 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 50 ether, 51 ether)
        );
        usdn.burnSharesFrom(USER_1, 51e36);
    }

    /**
     * @custom:scenario Burning shares from a user with insufficient balance
     * @custom:given An approved amount of max
     * @custom:when 150e36 shares are burned from the user
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnSharesFromInsufficientBalance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(UsdnInsufficientSharesBalance.selector, USER_1, 100e36, 150e36));
        usdn.burnSharesFrom(USER_1, 150e36);
    }

    /**
     * @custom:scenario Burn shares from another user when the amount corresponds to less than 1 wei of token
     * @custom:given User 1 has approved this contract to transfer 1 wei of tokens
     * @custom:when We try to burn 100 shares which equate to 0 tokens
     * @custom:then The allowance is decreased by 1 wei
     */
    function test_burnSharesFromLessThanOneWei() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 1);
        uint256 allowanceBefore = usdn.allowance(USER_1, address(this));
        assertEq(allowanceBefore, 1, "allowance before");

        uint256 sharesAmount = 100;
        uint256 tokenAmount = usdn.convertToTokens(sharesAmount);
        assertEq(tokenAmount, 0, "token amount");

        usdn.burnSharesFrom(USER_1, sharesAmount);
        assertEq(usdn.allowance(USER_1, address(this)), allowanceBefore - 1, "allowance after");
    }
}
