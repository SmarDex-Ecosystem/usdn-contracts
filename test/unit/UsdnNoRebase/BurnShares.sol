// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `burnShares` function of `UsdnNoRebase`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnNoRebaseBurnShares is UsdnNoRebaseTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.mintShares(address(this), 100 ether);
    }

    /**
     * @custom:scenario Users burning its tokens
     * @custom:when 50 USDN are burned
     * @custom:then The `Transfer` event is emitted with this address as the sender, the 0 address as the recipient and
     * an amount of 50 ether
     * @custom:and This address' balance is decreased by 50 ether
     */
    function test_burnShares() public {
        vm.expectEmit(address(usdn));
        emit Transfer(address(this), address(0), 50 ether);
        usdn.burnShares(50 ether);

        assertEq(usdn.balanceOf(address(this)), 50 ether, "balance after burn");
    }

    /**
     * @custom:scenario Burning with insufficient balance
     * @custom:when 150 USDN are burned from this address
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnSharesInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 100 ether, 150 ether)
        );
        usdn.burnShares(150 ether);
    }
}
