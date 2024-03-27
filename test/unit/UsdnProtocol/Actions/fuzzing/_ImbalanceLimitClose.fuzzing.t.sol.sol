// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitClose`
 * @custom:background Given a protocol instance in balanced state with random vault expo and long expo
 */
contract TestImbalanceLimitCloseFuzzing is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitClose` should pass on still balanced state
     * or revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitClose` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_checkImbalanceLimitClose(uint128 initialDeposit, uint128 initialLong, uint256 closeAmount)
        public
    {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // current balance long
        uint256 currentBalanceLong = protocol.getBalanceLong();
        // current total expo
        int256 currentTotalExpo = int256(protocol.getTotalExpo());
        // range withdrawalAmount properly
        closeAmount = bound(closeAmount, 1, currentBalanceLong);
        // total expo to remove
        uint256 totalExpoToRemove = closeAmount * uint256(currentTotalExpo) / params.initialLong;
        // new long expo
        int256 newLongExpo =
            (currentTotalExpo - int256(totalExpoToRemove)) - (int256(currentBalanceLong) - int256(closeAmount));

        // expected imbalance bps
        int256 imbalanceBps;
        if (newLongExpo > 0) {
            imbalanceBps =
                (int256(int128(params.initialDeposit)) - newLongExpo) * int256(protocol.BPS_DIVISOR()) / newLongExpo;
        }

        // initial close limit bps
        (,,, int256 initialCloseLimit) = protocol.getExpoImbalanceLimits();

        if (newLongExpo == 0) {
            // should revert because calculation is not possible
            vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        } else if (imbalanceBps >= initialCloseLimit) {
            // should revert with `imbalanceBp` close imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
            );
        }

        // call `i_checkImbalanceLimitClose` with totalExpoToRemove and closeAmount
        protocol.i_checkImbalanceLimitClose(totalExpoToRemove, closeAmount);
    }
}
