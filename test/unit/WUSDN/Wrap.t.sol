// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { WusdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `wrap` function of `WUSDN`
 * @custom:background Given this contract has 100 USDN
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnWrap is WusdnTokenFixture {
    /**
     * @custom:scenario Wrap USDN to WUSDN
     * @custom:given `usdnAmount` is minted to the msg.sender
     * @custom:when The half (usdnAmount / 2) is deposited to WUSDN
     * @custom:then The user balance of WUSDN should be equal to the shares of USDN / MAX_DIVISOR
     */
    function test_wrap() public {
        test_wrap(usdn.balanceOf(address(this)) / 2, address(this));
    }

    /**
     * @custom:scenario Wrap USDN to WUSDN
     * @custom:given `usdnAmount` is minted to another user
     * @custom:when The half (usdnAmount / 2) is deposited to WUSDN
     * @custom:then The user balance of WUSDN should be equal to the shares of USDN / MAX_DIVISOR
     */
    function test_wrapTo() public {
        test_wrap(usdn.balanceOf(address(this)) / 2, USER_1);
    }

    /**
     * @custom:scenario Wrap all USDN to WUSDN
     * @custom:given The contract has some USDN
     * @custom:when The contract wraps all USDN
     * @custom:then The contract balance of WUSDN should be equal to the shares of USDN / MAX_DIVISOR
     */
    function test_wrapAllBalance() public {
        test_wrap(usdn.balanceOf(address(this)), address(this));
    }

    /**
     * @custom:scenario Revert when wrapping USDN to WUSDN
     * @custom:when The contract tries to wrap more USDN than it has
     * @custom:then The transaction should revert with the error {WusdnInsufficientBalance}
     */
    function test_RevertWhen_wrapMoreThanBalance() public returns (uint256 wrappedAmount_) {
        uint256 usdnAmount = usdn.balanceOf(address(this)) + 1;
        vm.expectRevert(abi.encodeWithSelector(WusdnInsufficientBalance.selector, usdnAmount));
        wrappedAmount_ = wusdn.wrap(usdnAmount);
    }

    /**
     * @dev Helper function to test the wrap function
     * @param usdnAmount The amount of USDN to wrap
     * @param to The address to wrap to
     */
    function test_wrap(uint256 usdnAmount, address to) internal {
        uint256 wrappedAmount_ = usdn.convertToShares(usdnAmount) / wusdn.SHARES_RATIO();

        usdn.approve(address(wusdn), usdnAmount);

        vm.expectEmit(address(wusdn));
        emit Wrap(address(this), to, usdnAmount, wrappedAmount_);
        uint256 wrappedAmount = wusdn.wrap(usdnAmount, to);

        assertEq(wusdn.totalUsdnBalance(), usdnAmount, "total USDN supply in WUSDN");
        assertEq(wusdn.totalSupply(), wrappedAmount, "total WUSDN supply");
        assertEq(wusdn.balanceOf(to), wrappedAmount, "WUSDN shares");
        assertEq(wusdn.balanceOf(to), wrappedAmount_, "WUSDN balance");
    }
}
