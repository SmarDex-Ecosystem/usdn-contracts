// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `_updateShares` function of `USDN`
 * @custom:background The contract has the `MINTER_ROLE` and `REBASER_ROLE`
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnUpdateShares is UsdnTokenFixture {
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

    /**
     * @custom:scenario Minting shares that would overflow the total supply of shares
     * @custom:given The max amount of tokens has already been minted
     * @custom:when max amount of additional tokens are minted
     * @custom:then The transaction reverts with an overflow error
     */
    function test_RevertWhen_mintSharesOverflowTotal() public {
        usdn.i_updateShares(address(0), address(this), type(uint256).max, usdn.convertToTokens(type(uint256).max));
        uint256 token = usdn.convertToTokens(1);
        vm.expectRevert();
        usdn.i_updateShares(address(0), address(this), 1, token);
    }

    /* -------------------------------------------------------------------------- */
    /*                               TransferShares                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Transfer shares after a rebase
     * @custom:given 100 tokens are minted to a user
     * @custom:and The USDN was rebased with a random divisor
     * @custom:when The user transfers a random amount of shares to the test contract
     * @custom:then The user's balance is decreased by the transferred amount
     * @custom:and The contract's balance is increased by the transferred amount
     * @custom:and The token emits a `Transfer` event with the expected values
     * @custom:and The total shares supply remains unchanged
     * @param divisor The rebase divisor
     * @param sharesAmount The amount of shares to transfer
     */
    function testFuzz_transferShares(uint256 divisor, uint256 sharesAmount) public {
        usdn.mint(USER_1, 100 ether);
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 sharesBefore = usdn.sharesOf(USER_1);
        uint256 totalSharesBefore = usdn.totalShares();
        sharesAmount = bound(sharesAmount, 1, sharesBefore);
        uint256 tokenAmount = usdn.convertToTokens(sharesAmount);
        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(this), tokenAmount); // expected event
        usdn.i_updateShares(USER_1, address(this), sharesAmount, usdn.convertToTokens(sharesAmount));

        assertEq(usdn.sharesOf(USER_1), sharesBefore - sharesAmount, "balance of user");
        assertEq(usdn.sharesOf(address(this)), sharesAmount, "balance of contract");
        assertEq(usdn.totalShares(), totalSharesBefore, "total shares");
    }

    /**
     * @custom:scenario Transfer more shares than the balance
     * @custom:given 100 tokens are minted to a user
     * @custom:when The user tries to transfer more shares than they have
     * @custom:then The transaction reverts with the USDNInsufficientSharesBalance error
     */
    function test_RevertWhen_transferSharesInsufficientBalance() public {
        usdn.mint(USER_1, 100 ether);
        uint256 shares = usdn.sharesOf(USER_1);
        uint256 tokens = usdn.convertToTokens(shares + 1);
        vm.expectRevert(abi.encodeWithSelector(UsdnInsufficientSharesBalance.selector, USER_1, shares, shares + 1));
        usdn.i_updateShares(USER_1, address(this), shares + 1, tokens);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 BurnShares                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Burning a portion of the shares
     * @custom:given 100e36 shares are minted to a user
     * @custom:and A divisor of 0.5x MAX_DIVISOR
     * @custom:when 50e36 shares are burned
     * @custom:then The `Transfer` event is emitted with the user as the sender, the zero address as the recipient and
     * amount 100e18
     * @custom:and The user's shares are decreased by 50e36
     * @custom:and The user's balance is decreased by 100 tokens
     * @custom:and The total shares are decreased by 50e36
     * @custom:and The total supply is decreased by 100 tokens
     */
    function test_burnSharesPartial() public {
        usdn.mintShares(USER_1, 100e36);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        assertEq(usdn.sharesOf(USER_1), 100e36, "initial shares");
        assertEq(usdn.balanceOf(USER_1), 200 ether, "initial balance");

        uint256 shares = 50e36;
        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 100 ether); // expected event
        usdn.i_updateShares(USER_1, address(0), shares, usdn.convertToTokens(shares));

        assertEq(usdn.sharesOf(USER_1), shares, "shares after burn");
        assertEq(usdn.balanceOf(USER_1), 100 ether, "balance after burn");
        assertEq(usdn.totalShares(), shares, "total shares after burn");
        assertEq(usdn.totalSupply(), 100 ether, "total supply after burn");
    }

    /**
     * @custom:scenario Burning the entire shares balance
     * @custom:given 100e36 shares are minted to a user
     * @custom:when 100e36 shares are burned
     * @custom:then The `Transfer` event is emitted with the user as the sender, the zero address as the recipient and
     * amount 100 tokens
     * @custom:and The user's shares balance is zero
     * @custom:and The total shares is zero
     */
    function test_burnAllShares() public {
        usdn.mintShares(USER_1, 100e36);
        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), 100 ether); // expected event
        usdn.i_updateShares(USER_1, address(0), 100e36, usdn.convertToTokens(100e36));

        assertEq(usdn.sharesOf(USER_1), 0, "shares balance after burn");
        assertEq(usdn.totalShares(), 0, "total shares after burn");
    }

    /**
     * @custom:scenario Burning more shares than the balance
     * @custom:given 100e36 shares are minted to a user
     * @custom:when 101e36 shares are burned
     * @custom:then The transaction reverts with the `UsdnInsufficientSharesBalance` error
     */
    function test_RevertWhen_burnSharesInsufficientBalance() public {
        usdn.mintShares(USER_1, 100e36);
        uint256 tokens = usdn.convertToTokens(101e36);
        vm.expectRevert(abi.encodeWithSelector(UsdnInsufficientSharesBalance.selector, USER_1, 100e36, 101e36));
        usdn.i_updateShares(USER_1, address(0), 101e36, tokens);
    }
}
