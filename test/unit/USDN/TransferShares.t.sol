// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `transferShares` function of `USDN`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnTransferShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Transfer shares after a rebase
     * @custom:given The USDN was rebased with a random divisor
     * @custom:when The user transfers a random amount of shares to the test contract
     * @custom:then The user's balance is decreased by the transferred amount
     * @custom:and The contract's balance is increased by the transferred amount
     * @custom:and The token emits a `Transfer` event with the expected values
     * @custom:and The total shares supply remains unchanged
     * @param divisor The rebase divisor
     * @param sharesAmount The amount of shares to transfer
     */
    function testFuzz_transferShares(uint256 divisor, uint256 sharesAmount) public {
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
        vm.prank(USER_1);
        usdn.transferShares(address(this), sharesAmount);

        assertEq(usdn.sharesOf(USER_1), sharesBefore - sharesAmount, "balance of user");
        assertEq(usdn.sharesOf(address(this)), sharesAmount, "balance of contract");
        assertEq(usdn.totalShares(), totalSharesBefore, "total shares");
    }

    /**
     * @custom:scenario Transfer shares from zero address
     * @custom:when We try to transfer shares from the zero address
     * @custom:then The transaction reverts with the ERC20InvalidSender error
     */
    function test_RevertWhen_transferSharesFromZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        usdn.i_transferShares(address(0), USER_1, 1e36, 1e18);
    }

    /**
     * @custom:scenario Transfer shares to zero address
     * @custom:when We try to transfer shares to the zero address
     * @custom:then The transaction reverts with the ERC20InvalidReceiver error
     */
    function test_RevertWhen_transferSharesToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.transferShares(address(0), 1e36);
    }

    /**
     * @custom:scenario Transfer more shares than the balance
     * @custom:when The user tries to transfer more shares than they have
     * @custom:then The transaction reverts with the USDNInsufficientSharesBalance error
     */
    function test_RevertWhen_transferSharesInsufficientBalance() public {
        uint256 shares = usdn.sharesOf(USER_1);
        vm.expectRevert(abi.encodeWithSelector(UsdnInsufficientSharesBalance.selector, USER_1, shares, shares + 1));
        vm.prank(USER_1);
        usdn.transferShares(address(this), shares + 1);
    }
}
