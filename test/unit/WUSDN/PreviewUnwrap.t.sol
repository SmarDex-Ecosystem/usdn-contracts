// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Vm.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { WusdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `previewUnwrap` function of `WUSDN`
 * @custom:background Given this contract has 100 WUSDN
 * @custom:and The divisor is `MAX_DIVISOR`
 * @custom:and `usdnAmount` is minted to the msg.sender
 */
contract TestWusdnPreviewUnwrap is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
        uint256 usdnBalance = usdn.balanceOf(address(this));
        usdn.approve(address(wusdn), usdnBalance);
        wusdn.wrap(usdnBalance);
    }
    /**
     * @custom:scenario Preview unwrap USDN to WUSDN
     * @custom:when The half of the balance (`usdnAmount / 2`) is preview unwrapped to WUSDN
     * @custom:then The result of {previewUnwrap} should be equal to the shares of `usdnAmount` / `MAX_DIVISOR`
     */

    function test_previewUnwrapHalfBalance() public {
        test_previewUnwrap(usdn.balanceOf(address(this)) / 2);
    }

    /**
     * @custom:scenario Preview unwrap USDN to WUSDN
     * @custom:when The balance (`usdnAmount`) of the user is preview unwrapped to WUSDN
     * @custom:then The result of {previewUnwrap} should be equal to the shares of `usdnAmount` / `MAX_DIVISOR`
     */
    function test_previewUnwrap() public {
        test_previewUnwrap(usdn.balanceOf(address(this)));
    }

    /**
     * @custom:scenario Preview unwrap USDN to WUSDN
     * @custom:when `usdnAmount * 2` is preview unwrapped to WUSDN
     * @custom:then The result of {previewUnwrap} should be equal to the shares of `usdnAmount` / `MAX_DIVISOR`
     */
    function test_previewUnwrapTo() public {
        test_previewUnwrap(usdn.balanceOf(address(this)) * 2);
    }

    /**
     * @dev Helper function to test the {previewUnwrap} function
     * @param usdnAmount The amount of USDN to {previewUnwrap}
     */
    function test_previewUnwrap(uint256 usdnAmount) internal {
        uint256 shares = usdn.convertToShares(usdnAmount) * wusdn.SHARES_RATIO();
        uint256 unwrappedAmountExpected = wusdn.previewUnwrap(usdnAmount);

        vm.startPrank(USER_1);
        uint256 unwrappedAmountExpectedUSER1 = wusdn.previewUnwrap(usdnAmount);
        usdn.approve(address(wusdn), usdn.balanceOf(USER_1));
        uint256 unwrappedAmountObtained = wusdn.unwrap(usdnAmount);
        vm.stopPrank();

        assertEq(unwrappedAmountExpected, shares, "previewUnwrap == usdnAmount * SHARES_RATIO");
        assertEq(unwrappedAmountExpected, unwrappedAmountObtained, "previewUnwrap Expected == unwrap Obtained");
        assertEq(
            unwrappedAmountExpectedUSER1,
            unwrappedAmountExpected,
            "previewUnwrapForAnUser == previewUnwrapForAnotherUser"
        );
    }
}
