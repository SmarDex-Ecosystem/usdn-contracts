// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `burnShares` function of `USDN`
 * @custom:background Given a user with 100 tokens
 */
contract TestUsdnBurnShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
    }

    /**
     * @custom:scenario Burn shares call _burnShares with correct arguments
     * @custom:when 100 shares are burn by a user
     * @custom:then The `Transfer` event should be emitted with the sender address as the sender,
     * 0 address as the recipient, and an amount corresponding to the value calculated by the
     * `usdn.convertToTokens` function
     */
    function test_burnSharesCorrectArguments() public {
        uint256 tokensExpected = usdn.convertToTokens(100 ether);
        address sender = USER_1;
        vm.expectEmit(address(usdn));
        emit Transfer(sender, address(0), tokensExpected); // expected event
        vm.prank(sender);
        usdn.burnShares(100 ether);
    }
}
