// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `adjustMultiplier` function of `USDN`
 * @custom:background Given the current multiplier is 1
 */
contract TestUsdnAdjust is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Adjusting the multiplier
     * @custom:given A user with 100 USDN
     * @custom:and This contract has the `ADJUSTMENT_ROLE`
     * @custom:when The multiplier is adjusted to 1.000000001
     * @custom:then The `MultiplierAdjusted` event is emitted with the old and new multiplier
     * @custom:and The user's shares are unchanged
     * @custom:and The user's balance is multiplied by the new multiplier
     * @custom:and The total shares are unchanged
     * @custom:and The total supply is multiplied by the new multiplier
     */
    function test_adjustMultiplier() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));

        usdn.mint(USER_1, 100 ether);

        vm.expectEmit(true, true, false, false, address(usdn));
        emit MultiplierAdjusted(1 gwei, 1 gwei + 1); // expected event
        usdn.adjustMultiplier(1 gwei + 1);

        assertEq(usdn.sharesOf(USER_1), 100 ether * 10 ** usdn.decimalsOffset());
        assertEq(usdn.balanceOf(USER_1), 100 ether + 100 gwei);
        assertEq(usdn.totalShares(), 100 ether * 10 ** usdn.decimalsOffset());
        assertEq(usdn.totalSupply(), 100 ether + 100 gwei);
    }

    /**
     * @custom:scenario An unauthorized account tries to adjust the multiplier
     * @custom:given This contract has no role
     * @custom:when The multiplier is adjusted to 2
     * @custom:then The transaction reverts with the `AccessControlUnauthorizedAccount` error
     */
    function test_RevertWhen_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.ADJUSTMENT_ROLE()
            )
        );
        usdn.adjustMultiplier(2 gwei);
    }

    /**
     * @custom:scenario The multiplier is adjusted to the same value or smaller
     * @custom:given This contract has the `ADJUSTMENT_ROLE`
     * @custom:when The multiplier is adjusted to 1
     * @custom:or The multiplier is adjusted to 0.5
     * @custom:then The transaction reverts with the `UsdnInvalidMultiplier` error
     */
    function test_RevertWhen_invalidMultiplier() public {
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));

        vm.expectRevert(abi.encodeWithSelector(UsdnInvalidMultiplier.selector, 1 gwei));
        usdn.adjustMultiplier(1 gwei);

        vm.expectRevert(abi.encodeWithSelector(UsdnInvalidMultiplier.selector, 0.5 gwei));
        usdn.adjustMultiplier(0.5 gwei);
    }
}
