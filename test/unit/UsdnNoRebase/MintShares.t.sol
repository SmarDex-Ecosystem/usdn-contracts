// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { UsdnNoRebaseTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `mintShares` function of `USDN`
 * @custom:background Given this contract is the contract owner
 */
contract TestUsdnMintShares is UsdnNoRebaseTokenFixture {
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
     * @custom:scenario Minting shares without being the owner
     * @custom:when Shares are minted from an address that is not the owner
     * @custom:then The transaction reverts with the `OwnableUnauthorizedAccount` error
     */
    function test_RevertWhen_mintSharesFromNonOwnerAddress() public {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        usdn.mintShares(address(this), 100);
    }

    /**
     * @custom:scenario A user mints shares
     * @custom:when 100 shares are minted for a user
     * @custom:then The `Transfer` event should be emitted with the zero address as the sender, the user as the
     * recipient, and the minted amount
     * @custom:and The user's token balance should match the minted amount
     */
    function test_mintShares() public {
        vm.expectEmit(address(usdn));
        emit Transfer(address(0), USER_1, 100 ether);
        usdn.mint(address(this), 100 ether);

        assertEq(usdn.balanceOf(address(this)), 100 ether, "balance of user");
        assertEq(usdn.sharesOf(address(this)), 100 ether, "shares of user");
    }
}
