// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `_update` function of `USDN`
 */
contract TestUsdnUpdate is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
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
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
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
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
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
}
