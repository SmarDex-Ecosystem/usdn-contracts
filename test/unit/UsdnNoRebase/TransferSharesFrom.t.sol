// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `transferSharesFrom` function of `UsdnNoRebase`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnNoRebaseTransferSharesFrom is UsdnNoRebaseTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Transfer shares from a user to another user
     * @custom:when 100 shares are transfer from a user to the contract
     * @custom:then The `Transfer` event should be emitted with the sender address as the sender,
     * the contract address as the recipient, and the corresponding amount
     */
    function test_transferSharesFrom() public {
        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        uint256 sharesAmount = 100 ether;

        // conversion checks
        uint256 tokenAmount = usdn.convertToTokens(sharesAmount);
        assertEq(tokenAmount, sharesAmount, "1 share == 1 token in a no rebase setup");
        assertEq(tokenAmount, usdn.convertToTokensRoundUp(sharesAmount), "1 share == 1 token in a no rebase setup");
        assertEq(sharesAmount, usdn.convertToShares(tokenAmount), "1 share == 1 token in a no rebase setup");

        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(this), 100 ether);
        usdn.transferSharesFrom(USER_1, address(this), 100 ether);
    }

    /**
     * @custom:scenario Transfer shares from a user to another user with insufficient balance
     * @custom:when We try to transfer 100 ether shares from user 1 to this address
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_transferSharesInsufficientBalance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER_1, 100 ether, 150 ether)
        );
        usdn.transferSharesFrom(USER_1, address(this), 150 ether);
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
        usdn.transferSharesFrom(USER_1, address(0), 100 ether);
    }

    /**
     * @custom:scenario Transfer shares from another user with insufficient allowance
     * @custom:given User 1 has approved this contract to transfer 1 wei of their tokens
     * @custom:when We try to transfer 100e18 shares from user 1 to this contract
     * @custom:then The transaction reverts with the `ERC20InsufficientAllowance` error
     */
    function test_RevertWhen_transferSharesFromExceedsAllowance() public {
        vm.prank(USER_1);
        usdn.approve(address(this), 1);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 1, 100 ether)
        );
        usdn.transferSharesFrom(USER_1, address(this), 100 ether);
    }
}
