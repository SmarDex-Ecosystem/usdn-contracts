// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

/// @custom:feature The `setYieldRecipient` function of the `USDNr` contract
contract TestUsdnrSetYieldRecipient is UsdnrTokenFixture {
    /**
     * @custom:scenario Set a new yield recipient
     * @custom:when The `setYieldRecipient` function is called by the owner with a specific address
     * @custom:then The yield recipient is successfully updated
     */
    function test_setNewYieldRecipient() public {
        assertEq(usdnr.getYieldRecipient(), address(this), "yield recipient before");

        vm.expectEmit();
        emit IUsdnr.YieldRecipientUpdated(address(2));
        usdnr.setYieldRecipient(address(2));
        assertEq(usdnr.getYieldRecipient(), address(2), "yield recipient after");
    }

    /**
     * @custom:scenario Revert when a non-owner tries to set a new yield recipient
     * @custom:when The `setYieldRecipient` function is called by a non-owner address
     * @custom:then The functions should revert with an {Ownable.OwnableUnauthorizedAccount} error
     */
    function test_revertWhen_setYieldRecipientNotOwner() public {
        address nonOwnerUser = address(1);

        vm.prank(nonOwnerUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (nonOwnerUser)));
        usdnr.setYieldRecipient(address(2));
    }
}
