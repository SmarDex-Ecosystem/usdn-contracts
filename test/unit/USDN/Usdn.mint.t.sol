// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `mint` function of `USDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnMint is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
    }

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
        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.mint(USER_1, 100 ether);

        assertEq(usdn.balanceOf(USER_1), 100 ether, "balance of user");
        assertEq(usdn.sharesOf(USER_1), 100 ether * usdn.maxDivisor(), "shares of user");
        assertEq(usdn.totalSupply(), 100 ether, "total supply");
        assertEq(usdn.totalShares(), 100 ether * usdn.maxDivisor(), "total shares");
    }

    /**
     * @custom:scenario Minting tokens with a divisor
     * @custom:given This contract has the `ADJUSTMENT_ROLE`
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
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));

        usdn.adjustDivisor(usdn.maxDivisor() / 2);

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(address(0), USER_1, 100 ether); // expected event
        usdn.mint(USER_1, 100 ether);

        assertEq(usdn.balanceOf(USER_1), 100 ether, "balance of user");
        assertEq(usdn.sharesOf(USER_1), 50 ether * usdn.maxDivisor(), "shares of user");
        assertEq(usdn.totalSupply(), 100 ether, "total supply");
        assertEq(usdn.totalShares(), 50 ether * usdn.maxDivisor(), "total shares");
    }

    /**
     * @custom:scenario Minting maximum tokens at maximum divisor then decreasing divisor to min value
     * @custom:given This contract has the `ADJUSTMENT_ROLE`
     * @custom:when MAX_TOKENS is minted at the max divisor
     * @custom:and The divisor is adjusted to the minimum value
     * @custom:then The user's balance is MAX_TOKENS * MAX_DIVISOR / MIN_DIVISOR and nothing reverts
     */
    function test_mintMaxAndIncreaseMultiplier() public {
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));

        uint256 maxTokens = usdn.maxTokens();
        usdn.mint(USER_1, maxTokens);

        usdn.adjustDivisor(usdn.minDivisor());

        assertEq(usdn.balanceOf(USER_1), maxTokens * usdn.maxDivisor() / usdn.minDivisor());
    }

    /**
     * @custom:scenario An unauthorized account tries to mint tokens
     * @custom:given This contract has no role
     * @custom:when 100 tokens are minted to a user
     * @custom:then The transaction reverts with the `AccessControlUnauthorizedAccount` error
     */
    function test_RevertWhen_unauthorized() public {
        usdn.revokeRole(usdn.MINTER_ROLE(), address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.MINTER_ROLE()
            )
        );
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Minting tokens to the zero address
     * @custom:when 100 tokens are minted to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_mintToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.mint(address(0), 100 ether);
    }

    /**
     * @custom:scenario Minting tokens that would overflow the total supply of shares
     * @custom:given The max amount of tokens has already been minted
     * @custom:when 1 additional wei of token is minted
     * @custom:then The transaction reverts with the `UsdnTotalBalanceOverflow` error
     */
    function test_RevertWhen_mintOverflowTotal() public {
        usdn.mint(address(this), usdn.maxTokens());
        vm.expectRevert(UsdnTotalBalanceOverflow.selector);
        usdn.mint(address(this), 1);
    }
}
