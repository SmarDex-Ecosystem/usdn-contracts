// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `mintShares` function of `USDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnMintShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
    }

    /**
     * @custom:scenario Minting shares to the zero address
     * @custom:when 100 shares are minted to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_mintSharesToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.mintShares(address(0), 100);
    }

    /**
     * @custom:scenario Minting shares correctly converts shares into tokens
     * @custom:when 100 shares are minted for a user
     * @custom:then The `Transfer` event should be emitted with the zero address as the sender, the user as the
     * recipient, and an amount corresponding to the value calculated by the `usdn.convertToTokens` function
     * @custom:and The user's token balance should match the value calculated by the `usdn.convertToTokens` function
     */
    function test_mintSharesConversion() public {
        uint256 tokensExpected = usdn.convertToTokens(100 ether * usdn.MAX_DIVISOR());
        vm.expectEmit(address(usdn));
        emit Transfer(address(0), USER_1, tokensExpected); // expected event
        usdn.mintShares(USER_1, 100 ether * usdn.MAX_DIVISOR());

        assertEq(usdn.balanceOf(USER_1), tokensExpected, "balance of user");
    }
}
