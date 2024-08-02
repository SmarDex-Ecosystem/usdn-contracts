// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../test/utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `burnShares` function of `USDN`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnBurnTokens is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Burn shares call _burnShares with correct arguments
     * @custom:when 100 tokens are burned by a user
     * @custom:then The `Transfer` event should be emitted with the sender address as the sender and
     * 0 address as the recipient, and the amount burned
     */
    function test_burnTokensCorrectArguments() public {
        uint256 balanceBefore = usdn.balanceOf(USER_1);
        uint256 amountToBurn = 100 ether;
        vm.expectEmit(address(usdn));
        emit Transfer(USER_1, address(0), amountToBurn); // expected event
        vm.prank(USER_1);
        usdn.burn(amountToBurn);
        assertEq(usdn.balanceOf(USER_1), balanceBefore - amountToBurn, "Balance decreased by amountToBurn");
    }
}
