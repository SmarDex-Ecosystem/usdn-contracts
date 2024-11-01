// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { WusdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing of the WUSDN token functions
 * @custom:background Given this contract has the MINTER_ROLE and REBASER_ROLE of the USDN token
 */
contract TestWusdnFuzzing is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.mint(address(this), type(uint128).max);
        usdn.approve(address(wusdn), usdn.balanceOf(address(this)));
        wusdn.wrapShares(usdn.sharesOf(address(this)), address(this));
    }

    /**
     * @custom:scenario Try to wrap total balance after rebase
     * @custom:given A divisor between MAX_DIVISOR and MIN_DIVISOR
     * @custom:and An amount of shares between 0 and type(uint128).max
     * @custom:when We mint the amount of shares to a user
     * @custom:and We rebase the USDN token with the divisor
     * @custom:then The wrap function should not revert
     * @param divisor The divisor to use
     * @param usdnShares The amount of shares to mint
     */
    function testFuzz_wrap_totalBalance_afterRebase(uint256 divisor, uint128 usdnShares) public {
        uint256 initialSharesBalance = usdn.sharesOf(USER_1);
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        usdn.mintShares(USER_1, usdnShares);

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 userBalance = usdn.balanceOf(USER_1);
        if (usdn.sharesOf(USER_1) < wusdn.SHARES_RATIO() || usdn.convertToShares(userBalance) < wusdn.SHARES_RATIO()) {
            return;
        }

        vm.startPrank(USER_1);

        usdn.approve(address(wusdn), userBalance);
        uint256 wrappedAmount = wusdn.wrap(userBalance);
        wusdn.unwrap(wrappedAmount);

        vm.stopPrank();
        assertEq(usdn.sharesOf(USER_1), usdnShares + initialSharesBalance);
    }

    /**
     * @custom:scenario Compare the {previewWrapShares} and {wrapShares} functions
     * @custom:given A divisor between `MAX_DIVISOR` and `MIN_DIVISOR`
     * @custom:and An amount of shares between 0 and type(uint128).max
     * @custom:when We wrap the amount of shares
     * @custom:then The {wrapShares} function should return the same amount as {previewWrapShares}
     * @param divisor The divisor to use
     * @param usdnShares The amount of shares to mint for the user
     * @param shareToWrap The amount of shares to wrap
     */
    function testFuzz_previewWrapShares(uint256 divisor, uint256 usdnShares, uint256 shareToWrap) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        usdnShares = bound(usdnShares, wusdn.SHARES_RATIO(), type(uint128).max);
        usdn.mintShares(USER_1, usdnShares);
        shareToWrap = bound(shareToWrap, wusdn.SHARES_RATIO(), usdnShares);

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        vm.startPrank(USER_1);

        usdn.approve(address(wusdn), usdn.convertToTokensRoundUp(shareToWrap));
        uint256 wrappedAmountPreview = wusdn.previewWrapShares(shareToWrap);
        uint256 wrappedAmount = wusdn.wrapShares(shareToWrap, address(this));

        vm.stopPrank();

        assertEq(wrappedAmount, wrappedAmountPreview);
    }

    /**
     * @custom:scenario Compare the {previewUnwrap} and {unwrap} functions
     * @custom:given A divisor between `MAX_DIVISOR` and `MIN_DIVISOR`
     * @custom:and An amount of WUSDN between 0 and type(uint128).max
     * @custom:when We unwrap the amount of WUSDN
     * @custom:then The {unwrapShares} function should return the same amount as {previewUnwrapShares}
     * @param divisor The divisor to use
     * @param wusdnAmount The amount of WUSDN to unwrap
     */
    function testFuzz_previewUnwrapShares(uint256 divisor, uint256 wusdnAmount) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        wusdn.transfer(USER_1, type(uint128).max);
        wusdnAmount = bound(wusdnAmount, 0, type(uint128).max);
        uint256 sharesOf = usdn.sharesOf(USER_1);

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        vm.startPrank(USER_1);

        wusdn.approve(address(wusdn), wusdnAmount);
        uint256 usdnSharesAmount = wusdn.previewUnwrapShares(wusdnAmount);
        wusdn.unwrap(wusdnAmount, USER_1);

        vm.stopPrank();

        assertEq(sharesOf + usdnSharesAmount, usdn.sharesOf(USER_1));
    }
}
