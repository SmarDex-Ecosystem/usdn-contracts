// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { WusdnTokenFixture } from "./utils/Fixtures.sol";

import "forge-std/Vm.sol";

/**
 * @custom:feature The {previewWrap} function of WUSDN
 * @custom:background Given this contract has 100 USDN
 * @custom:and The divisor is `MAX_DIVISOR`
 */
contract TestWusdnPreviewWrap is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.approve(address(wusdn), usdn.balanceOf(address(this)));
        usdn.mint(USER_1, 200 ether);
    }
    /**
     * @custom:scenario Preview wrap USDN to WUSDN
     * @custom:given `usdnAmount` is minted to the msg.sender
     * @custom:when The half of the balance (`usdnAmount / 2`) is preview wrapped to WUSDN
     * @custom:then The result of {previewWrap} should be equal to the shares of `usdnAmount` / `MAX_DIVISOR`
     */

    function test_previewWrapHalfBalance() public {
        test_previewWrap(usdn.balanceOf(address(this)) / 2);
    }

    /**
     * @custom:scenario Preview wrap USDN to WUSDN
     * @custom:given `usdnAmount` is minted to the msg.sender
     * @custom:when The balance (`usdnAmount`) of the user is preview wrapped to WUSDN
     * @custom:then The result of {previewWrap} should be equal to the shares of `usdnAmount` / `MAX_DIVISOR`
     */
    function test_previewWrap() public {
        test_previewWrap(usdn.balanceOf(address(this)));
    }

    /**
     * @custom:scenario Preview wrap USDN to WUSDN
     * @custom:given `usdnAmount` is minted to the msg.sender
     * @custom:when `usdnAmount * 2` is preview wrapped to WUSDN
     * @custom:then The result of {previewWrap} should be equal to the shares of `usdnAmount` / `MAX_DIVISOR`
     */
    function test_previewWrapTo() public {
        test_previewWrap(usdn.balanceOf(address(this)) * 2);
    }

    /**
     * @dev Helper function to test the {previewWrap} function
     * @param usdnAmount The amount of USDN to {previewWrap}
     */
    function test_previewWrap(uint256 usdnAmount) internal {
        uint256 shares = usdn.convertToShares(usdnAmount) / wusdn.SHARES_RATIO();
        uint256 wrappedAmountExpected = wusdn.previewWrap(usdnAmount);

        vm.startPrank(USER_1);
        uint256 wrappedAmountExpectedUSER1 = wusdn.previewWrap(usdnAmount);
        usdn.approve(address(wusdn), usdn.balanceOf(USER_1));
        uint256 wrappedAmountObtained = wusdn.wrap(usdnAmount);
        vm.stopPrank();

        assertEq(wrappedAmountExpected, shares, "previewWrap == usdnAmount / SHARES_RATIO");
        assertEq(wrappedAmountExpected, wrappedAmountObtained, "previewWrap Expected == wrap Obtained");
        assertEq(wrappedAmountExpectedUSER1, wrappedAmountExpected, "previewWrapForAnUser == previewWrapForAnotherUser");
    }
}
