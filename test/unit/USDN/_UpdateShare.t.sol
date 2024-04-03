// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `_update` function of `USDN`
 */
contract TestUsdnUpdateShare is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
    }

    /* -------------------------------------------------------------------------- */
    /*                                  MintShare                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Minting tokens
     * @custom:when 100e36 shares are minted to a user
     * @custom:then The `Transfer` event is emitted with the zero address as the sender, the user as the recipient and
     * amount 100e18
     * @custom:and The user's shares balance is 100e36
     * @custom:and The user's balance is 100e18
     * @custom:and The total shares are 100e36
     * @custom:and The total supply is 100e18
     */
    function test_mintShares() public {
        vm.expectEmit(address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.i_updateShares(
            address(0), USER_1, 100 ether * usdn.MAX_DIVISOR(), usdn.convertToTokens(100 ether * usdn.MAX_DIVISOR())
        );

        assertEq(usdn.sharesOf(USER_1), 100 ether * usdn.MAX_DIVISOR(), "shares of user");
        assertEq(usdn.balanceOf(USER_1), 100 ether, "balance of user");
        assertEq(usdn.totalShares(), 100 ether * usdn.MAX_DIVISOR(), "total shares");
        assertEq(usdn.totalSupply(), 100 ether, "total supply");
    }

    /**
     * @custom:scenario Minting tokens with a divisor
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to 0.5x MAX_DIVISOR
     * @custom:and 50e36 shares are minted to a user
     * @custom:then The `Transfer` event is emitted with the zero address as the sender, the user as the recipient and
     * amount 100e18
     * @custom:and The user's shares are 50e36
     * @custom:and The user's balance is 100e18
     * @custom:and The total shares are 50e36
     * @custom:and The total supply is 100e18
     */
    function test_mintSharesWithMultiplier() public {
        usdn.rebase(usdn.MAX_DIVISOR() / 2);

        vm.expectEmit(address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.i_updateShares(
            address(0), USER_1, 50 ether * usdn.MAX_DIVISOR(), usdn.convertToTokens(50 ether * usdn.MAX_DIVISOR())
        );

        assertEq(usdn.sharesOf(USER_1), 50 ether * usdn.MAX_DIVISOR(), "shares of user");
        assertEq(usdn.balanceOf(USER_1), 100 ether, "balance of user");
        assertEq(usdn.totalShares(), 50 ether * usdn.MAX_DIVISOR(), "total shares");
        assertEq(usdn.totalSupply(), 100 ether, "total supply");
    }

    /**
     * @custom:scenario Minting uint256.max shares at maximum divisor then decreasing divisor to min value
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when uint256.max shares are minted at the max divisor
     * @custom:and The divisor is adjusted to the minimum value
     * @custom:then The user's shares is uint256.max and nothing reverts
     * @custom:and The user's balance is MAX_TOKENS
     */
    function test_mintSharesMaxAndIncreaseMultiplier() public {
        usdn.i_updateShares(address(0), USER_1, type(uint256).max, usdn.convertToTokens(type(uint256).max));

        usdn.rebase(usdn.MIN_DIVISOR());

        assertEq(usdn.sharesOf(USER_1), type(uint256).max, "shares");
        assertEq(usdn.balanceOf(USER_1), usdn.maxTokens(), "tokens");
    }
}
