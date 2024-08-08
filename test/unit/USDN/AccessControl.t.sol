// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

import { IRebaseCallback } from "../../../src/interfaces/Usdn/IRebaseCallback.sol";

/**
 * @custom:feature The privileged functions of USDN
 * @custom:background Given a usdn instance that was initialized with default params
 */
contract TestUsdnAccessControl is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.DEFAULT_ADMIN_ROLE(), ADMIN);
        usdn.revokeRole(usdn.DEFAULT_ADMIN_ROLE(), address(this));
    }

    /**
     * @custom:scenario Call all privileged functions with a wallet that does not have the required role
     * @custom:when A user without the required role calls all privileged functions
     * @custom:then Each function should revert with the error corresponding to the role
     */
    function test_RevertWhen_unauthorized() public {
        bytes memory minterUnauthorizedError = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.MINTER_ROLE()
        );
        bytes memory rebaserUnauthorizedError = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.REBASER_ROLE()
        );
        bytes memory adminUnauthorizedError = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.DEFAULT_ADMIN_ROLE()
        );

        vm.expectRevert(minterUnauthorizedError);
        usdn.mint(address(this), 100 ether);

        vm.expectRevert(minterUnauthorizedError);
        usdn.mintShares(address(this), 100);

        uint256 maxDivisor = usdn.MAX_DIVISOR();
        vm.expectRevert(rebaserUnauthorizedError);
        usdn.rebase(maxDivisor / 2);

        vm.expectRevert(adminUnauthorizedError);
        usdn.setRebaseHandler(IRebaseCallback(address(1)));
    }
}
