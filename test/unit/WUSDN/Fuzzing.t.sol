// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature Fuzzing of the WUSDN token functions
 * @custom:background Given this contract has the MINTER_ROLE and REBASER_ROLE of the USDN token
 */
contract TestWusdnFuzzing is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
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
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        usdn.mintShares(USER_1, usdnShares);

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 userBalance = usdn.balanceOf(USER_1);
        vm.startPrank(USER_1);

        usdn.approve(address(wusdn), userBalance);
        wusdn.wrap(userBalance);

        vm.stopPrank();
    }
}
