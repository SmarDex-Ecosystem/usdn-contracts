// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { Usdnr } from "../../../src/Usdn/Usdnr.sol";

/// @custom:feature The constructor features of `USDnr` contract
contract TestUsdnrConstructor is UsdnrTokenFixture {
    /**
     * @custom:scenario The constructor sets the correct values
     * @custom:when The contract is deployed
     * @custom:then The name and symbol are set correctly
     * @custom:then The USDN address is set correctly
     * @custom:then The owner is set correctly
     */
    function test_usdnrConstructor() public {
        usdnr = new Usdnr(usdn, address(this));

        assertEq(usdnr.name(), "USDN Reserve", "name");
        assertEq(usdnr.symbol(), "USDnr", "symbol");
        assertEq(address(usdnr.USDN()), address(usdn), "USDN address");
        assertEq(usdnr.owner(), address(this), "owner");
    }

    /**
     * @custom:scenario Ownable2Step functionality
     * @custom:when The contract is deployed and ownership is transferred
     * @custom:then The owner and pending owner are set correctly
     * @custom:then The new owner can accept ownership
     */
    function test_ownable2Step() public {
        usdnr = new Usdnr(usdn, address(this));

        assertEq(usdnr.owner(), address(this), "owner");
        usdnr.transferOwnership(address(1));
        assertEq(usdnr.pendingOwner(), address(1), "pending owner");
        assertEq(usdnr.owner(), address(this), "owner");

        vm.prank(address(1));
        usdnr.acceptOwnership();
        assertEq(usdnr.owner(), address(1), "owner");
        assertEq(usdnr.pendingOwner(), address(0), "pending owner");
    }
}
