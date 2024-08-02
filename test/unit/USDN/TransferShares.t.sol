// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

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
     * @custom:scenario Transfer shares call _transferShares with correct arguments
     * @custom:when 100 shares are transfer from a user to the contract
     * @custom:then The `Transfer` event should be emitted with the sender address as the sender,
     * the contract address as the recipient, and an amount corresponding to the value calculated by the
     * `usdn.convertToTokens` function
     */
    function test_transferSharesCorrectArguments() public {
        uint256 tokensExpected = usdn.convertToTokens(100 ether);
        address sender = USER_1;
        vm.expectEmit(address(usdn));
        emit Transfer(sender, address(this), tokensExpected); // expected event
        vm.prank(sender);
        usdn.transferShares(address(this), 100 ether);
    }
}
