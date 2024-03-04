// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `rebase` function of `USDN`
 * @custom:background Given the current divisor is MAX_DIVISOR
 */
contract TestUsdnRebase is UsdnTokenFixture {
    uint256 internal maxDivisor;
    uint256 internal minDivisor;

    function setUp() public override {
        super.setUp();
        maxDivisor = usdn.MAX_DIVISOR();
        minDivisor = usdn.MIN_DIVISOR();
    }

    /**
     * @custom:scenario Getting the divisor
     * @custom:when The `divisor` function is called
     * @custom:then The result is MAX_DIVISOR
     */
    function test_getDivisor() public {
        assertEq(usdn.divisor(), maxDivisor);
    }

    /**
     * @custom:scenario Rebase by adjusting the divisor
     * @custom:given A user with 100 USDN
     * @custom:and This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MAX_DIVISOR / 10
     * @custom:then The `Rebase` event is emitted with the old and new divisor
     * @custom:and The user's shares are unchanged
     * @custom:and The user's balance is grown proportionally (10 times)
     * @custom:and The total shares are unchanged
     * @custom:and The total supply is grown proportionally (10 times)
     */
    function test_rebase() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        usdn.mint(USER_1, 100 ether);

        vm.expectEmit(address(usdn));
        emit Rebase(maxDivisor, maxDivisor / 10); // expected event
        usdn.rebase(maxDivisor / 10);

        assertEq(usdn.sharesOf(USER_1), 100 ether * maxDivisor, "shares of user");
        assertEq(usdn.balanceOf(USER_1), 100 ether * 10, "balance of user");
        assertEq(usdn.totalShares(), 100 ether * maxDivisor, "total shares");
        assertEq(usdn.totalSupply(), 100 ether * 10, "total supply");
    }

    /**
     * @custom:scenario An unauthorized account tries to rebase
     * @custom:given This contract has no role
     * @custom:when The divisor is adjusted to 0.5x its initial value
     * @custom:then The transaction reverts with the `AccessControlUnauthorizedAccount` error
     */
    function test_RevertWhen_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), usdn.REBASER_ROLE()
            )
        );
        usdn.rebase(maxDivisor / 2);
    }

    /**
     * @custom:scenario The divisor is adjusted to the same value or larger
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MAX_DIVISOR
     * @custom:or The divisor is adjusted to 2x MAX_DIVISOR
     * @custom:then The transaction reverts with the `UsdnInvalidDivisor` error
     */
    function test_RevertWhen_invalidDivisor() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        vm.expectRevert(abi.encodeWithSelector(UsdnInvalidDivisor.selector, maxDivisor));
        usdn.rebase(maxDivisor);

        vm.expectRevert(abi.encodeWithSelector(UsdnInvalidDivisor.selector, 2 * maxDivisor));
        usdn.rebase(2 * maxDivisor);
    }

    /**
     * @custom:scenario The divisor is adjusted to a value that is too small
     * @custom:given This contract has the `REBASER_ROLE`
     * @custom:when The divisor is adjusted to MIN_DIVISOR - 1
     * @custom:then The transaction reverts with the `UsdnInvalidDivisor` error
     */
    function test_RevertWhen_divisorTooSmall() public {
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));

        vm.expectRevert(abi.encodeWithSelector(UsdnInvalidDivisor.selector, minDivisor - 1));
        usdn.rebase(minDivisor - 1);
    }
}
