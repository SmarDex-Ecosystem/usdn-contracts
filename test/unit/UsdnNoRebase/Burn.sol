// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `burn` function of `UsdnNoRebase`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnNoRebaseBurn is UsdnNoRebaseTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.mint(address(this), 100 ether);
    }

    /**
     * @custom:scenario User burning its tokens
     * @custom:when 50 USDN are burned
     * @custom:then The `Transfer` event is emitted with this address as the sender, this contract as the recipient and
     * amount 50
     * @custom:and This address' balance is decreased by 50
     */
    function test_burn() public {
        vm.expectEmit(address(usdn));
        emit Transfer(address(this), address(0), 50 ether);
        usdn.burn(50 ether);

        assertEq(usdn.balanceOf(address(this)), 50 ether, "balance after burn");
    }

    /**
     * @custom:scenario Burning with insufficient balance
     * @custom:when 150 USDN are burned from this address
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_burnInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 100 ether, 150 ether)
        );
        usdn.burn(150 ether);
    }
}
