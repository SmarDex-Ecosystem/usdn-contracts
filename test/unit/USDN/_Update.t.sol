// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `_update` function of `USDN`
 * @custom:background The contract has the `MINTER_ROLE` and `REBASER_ROLE`
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnUpdate is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Mint                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Minting tokens
     * @custom:when 100 tokens are minted to a user
     * @custom:then The `Transfer` event is emitted with the zero address as the sender, the user as the recipient and
     * amount 100
     * @custom:and The user's balance is 100
     * @custom:and The user's shares are 100
     * @custom:and The total supply is 100
     * @custom:and The total shares are 100
     */
    function test_mint() public {
        vm.expectEmit(address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.i_update(address(0), USER_1, 100 ether);

        assertEq(usdn.balanceOf(USER_1), 100 ether, "balance of user");
        assertEq(usdn.sharesOf(USER_1), 100 ether * usdn.MAX_DIVISOR(), "shares of user");
        assertEq(usdn.totalSupply(), 100 ether, "total supply");
        assertEq(usdn.totalShares(), 100 ether * usdn.MAX_DIVISOR(), "total shares");
    }

    /**
     * @custom:scenario Minting tokens with a divisor
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to 0.5x MAX_DIVISOR
     * @custom:and 100 tokens are minted to a user
     * @custom:then The `Transfer` event is emitted with the zero address as the sender, the user as the recipient and
     * amount 100
     * @custom:and The user's balance is 100
     * @custom:and The user's shares are 50
     * @custom:and The total supply is 100
     * @custom:and The total shares are 50
     */
    function test_mintWithMultiplier() public {
        usdn.rebase(usdn.MAX_DIVISOR() / 2);

        vm.expectEmit(address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.i_update(address(0), USER_1, 100 ether);

        assertEq(usdn.balanceOf(USER_1), 100 ether, "balance of user");
        assertEq(usdn.sharesOf(USER_1), 50 ether * usdn.MAX_DIVISOR(), "shares of user");
        assertEq(usdn.totalSupply(), 100 ether, "total supply");
        assertEq(usdn.totalShares(), 50 ether * usdn.MAX_DIVISOR(), "total shares");
    }

    /**
     * @custom:scenario Minting maximum tokens at maximum divisor then decreasing divisor to min value
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when MAX_TOKENS is minted at the max divisor
     * @custom:and The divisor is adjusted to the minimum value
     * @custom:then The user's balance is MAX_TOKENS * MAX_DIVISOR / MIN_DIVISOR and nothing reverts
     */
    function test_mintMaxAndIncreaseMultiplier() public {
        uint256 maxTokens = usdn.maxTokens();
        usdn.i_update(address(0), USER_1, maxTokens);

        usdn.rebase(usdn.MIN_DIVISOR());

        assertEq(usdn.balanceOf(USER_1), maxTokens * usdn.MAX_DIVISOR() / usdn.MIN_DIVISOR());
    }

    /**
     * @custom:scenario Minting tokens that would overflow the total supply of shares
     * @custom:given The max amount of tokens has already been minted
     * @custom:when max amount of additional tokens are minted
     * @custom:then The transaction reverts with the `UsdnTotalSupplyOverflow` error
     */
    function test_RevertWhen_mintOverflowTotal() public {
        uint256 max = usdn.maxTokens();
        usdn.i_update(address(0), address(this), max);
        vm.expectRevert(UsdnTotalSupplyOverflow.selector);
        usdn.i_update(address(0), address(this), max);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Burn                                    */
    /* -------------------------------------------------------------------------- */

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
        usdn.mint(USER_1, 100 ether);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        assertEq(usdn.balanceOf(USER_1), 200 ether, "initial balance");
        assertEq(usdn.sharesOf(USER_1), 100 ether * usdn.MAX_DIVISOR(), "initial shares");

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 50 ether); // expected event
        usdn.i_update(USER_1, address(0), 50 ether);

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
        usdn.mint(USER_1, 100 ether);
        usdn.rebase(9 * usdn.MAX_DIVISOR() / 10);
        assertEq(usdn.balanceOf(USER_1), 111_111_111_111_111_111_111, "initial balance");
        assertEq(usdn.sharesOf(USER_1), 100 ether * usdn.MAX_DIVISOR(), "initial shares");

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 111_111_111_111_111_111_111); // expected event
        usdn.i_update(USER_1, address(0), 111_111_111_111_111_111_111);

        assertEq(usdn.balanceOf(USER_1), 0, "balance after burn");
        assertEq(usdn.totalSupply(), 0, "total supply after burn");
    }

    /**
     * @custom:scenario Burning more than the balance
     * @custom:when 101 USDN are burned
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnInsufficientBalance() public {
        usdn.mint(USER_1, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 101 ether)
        );
        usdn.i_update(USER_1, address(0), 101 ether);
    }

    /**
     * @custom:scenario Burning more than the balance
     * @custom:given A divisor of 0.5x MAX_DIVISOR
     * @custom:and A user with 200 USDN
     * @custom:when 201 USDN are burned
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnInsufficientBalanceWithMultiplier() public {
        usdn.mint(USER_1, 100 ether);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        assertEq(usdn.balanceOf(USER_1), 200 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 200 ether, 201 ether)
        );
        usdn.i_update(USER_1, address(0), 201 ether);
    }
}
