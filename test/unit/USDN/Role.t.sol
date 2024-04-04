// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The role functions of the usdn
 * @custom:background Given a usdn instance that was initialized with default params
 */
contract TestUsdnRole is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call all role functions with wallet dose not have the right role.
     * @custom:given The initial usdn state.
     * @custom:when wallet who not have the right role call the role functions.
     * @custom:then Each functions should revert with the error correspondign to the role.
     */
    function test_RevertWhen_walletNotHaveRoleCallRoleFunctions() external {
        bytes memory minterUnauthorizedError = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.MINTER_ROLE()
        );
        bytes memory rebaserUnauthorizedError = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.REBASER_ROLE()
        );

        vm.expectRevert(minterUnauthorizedError);
        usdn.mint(address(this), 100 ether);

        vm.expectRevert(minterUnauthorizedError);
        usdn.mintShares(address(this), 100);

        uint256 maxDivisor = usdn.MAX_DIVISOR();
        vm.expectRevert(rebaserUnauthorizedError);
        usdn.rebase(maxDivisor / 2);
    }
}
