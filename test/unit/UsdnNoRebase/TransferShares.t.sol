// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `transferShares` function of `UsdnNoRebase`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnNoRebaseTransferShares is UsdnNoRebaseTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.mint(address(this), 100 ether);
    }

    /**
     * @custom:scenario Transfer shares to another user
     * @custom:when 100 shares are transfer from a user to the contract
     * @custom:then The `Transfer` event should be emitted with the sender address as the sender,
     * the contract address as the recipient, and the corresponding amount
     */
    function test_transferShares() public {
        vm.expectEmit(address(usdn));
        emit Transfer(address(this), USER_1, 100 ether);
        usdn.transferShares(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Transfer shares to another user with insufficient balance
     * @custom:when We try to transfer 100 ether shares to user 1
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_transferSharesInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 100 ether, 150 ether)
        );
        usdn.transferShares(USER_1, 150 ether);
    }

    /**
     * @custom:scenario Transfer shares to the zero address
     * @custom:when We try to transfer shares to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_transferSharesToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.transferShares(address(0), 100 ether);
    }
}
