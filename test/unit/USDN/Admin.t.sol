// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The admin functions of the usdn
 * @custom:background Given a usdn instance that was initialized with default params
 */
contract TestUsdnAdmin is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call all admin functions from non contract admin.
     * @custom:given The initial usdn state.
     * @custom:when Non admin wallet trigger admin contract function.
     * @custom:then Each functions should revert with the same error.
     */
    function test_RevertWhen_nonAdminWalletCallAdminFunctions() external {
        bytes memory unauthorizedError = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.MINTER_ROLE()
        );

        vm.expectRevert(unauthorizedError);
        usdn.mint(USER_1, 100 ether);
    }
}
