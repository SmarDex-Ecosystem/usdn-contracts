// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `transferSharesFrom` function of `USDN`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnTransferSharesFrom is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Transfer shares after a rebase
     * @custom:given The USDN was rebased with a random divisor
     * @custom:and User 1 has approved this contract to transfer their full balance
     * @custom:when The test contract transfers a random amount of shares from user 1 to the test contract
     * @custom:then The user's balance is decreased by the transferred amount
     * @custom:and The contract's balance is increased by the transferred amount
     * @custom:and The token emits a `Transfer` event with the expected values
     * @custom:and The total shares supply remains unchanged
     * @param divisor The rebase divisor
     * @param sharesAmount The amount of shares to transfer
     */
    function testFuzz_transferSharesFrom(uint256 divisor, uint256 sharesAmount) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 userShares = usdn.sharesOf(USER_1);
        uint256 approveTokens = usdn.convertToTokensRoundUp(userShares);
        vm.prank(USER_1);
        usdn.approve(address(this), approveTokens);

        uint256 sharesBefore = usdn.sharesOf(USER_1);
        uint256 totalSharesBefore = usdn.totalShares();
        sharesAmount = bound(sharesAmount, 1, sharesBefore);
        uint256 tokenAmount = usdn.convertToTokens(sharesAmount);
        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(this), tokenAmount); // expected event
        usdn.transferSharesFrom(USER_1, address(this), sharesAmount);

        assertEq(usdn.sharesOf(USER_1), sharesBefore - sharesAmount, "balance of user");
        assertEq(usdn.sharesOf(address(this)), sharesAmount, "balance of contract");
        assertEq(usdn.totalShares(), totalSharesBefore, "total shares");
    }

    /**
     * @custom:scenario Transfer shares from another user to zero address
     * @custom:given User 1 has approved this contract to transfer their tokens
     * @custom:when We try to transfer user 1's shares to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_transferSharesFromToZeroAddress() public {
        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.transferSharesFrom(USER_1, address(0), 1e36);
    }

    /**
     * @custom:scenario Transfer shares from another user with insufficient allowance
     * @custom:given User 1 has approved this contract to transfer 1 wei of their tokens
     * @custom:when We try to transfer 1e20 shares from user 1 to this contract
     * @custom:then The transaction reverts with the `ERC20InsufficientAllowance` error
     */
    function test_RevertWhen_transferSharesFromExceedsAllowance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 1);

        uint256 sharesAmount = 1e20;
        uint256 tokenAmount = usdn.convertToTokens(sharesAmount);
        assertGt(tokenAmount, 1, "token amount");

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 1, tokenAmount)
        );
        usdn.transferSharesFrom(USER_1, address(this), sharesAmount);
    }

    /**
     * @custom:scenario Transfer shares from another user when the amount corresponds to less than 1 wei of token
     * @custom:given User 1 has approved this contract to transfer 1 wei of tokens
     * @custom:when We try to transfer 100 shares which equate to 0 tokens
     * @custom:then The allowance is decreased by 1 wei
     */
    function test_transferSharesFromLessThanOneWei() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 1);
        uint256 allowanceBefore = usdn.allowance(USER_1, address(this));
        assertEq(allowanceBefore, 1, "allowance before");

        uint256 sharesAmount = 100;
        uint256 tokenAmount = usdn.convertToTokens(sharesAmount);
        assertEq(tokenAmount, 0, "token amount");

        usdn.transferSharesFrom(USER_1, address(this), sharesAmount);
        assertEq(usdn.allowance(USER_1, address(this)), allowanceBefore - 1, "allowance after");
    }
}
