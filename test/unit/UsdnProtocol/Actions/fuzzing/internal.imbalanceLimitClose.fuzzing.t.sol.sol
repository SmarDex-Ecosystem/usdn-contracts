// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitClose`
 * @custom:background Given a protocol instance in balanced state with random expos
 */
contract FuzzingImbalanceLimitClose is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitClose` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitClose` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitClose(uint128 initialDeposit, uint128 initialLong, uint256 closeAmount) public {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // current balance long
        uint256 currentBalanceLong = protocol.getBalanceLong();
        // current total expo
        int256 currentTotalExpo = int256(protocol.getTotalExpo());
        // range withdrawalAmount properly
        closeAmount = bound(closeAmount, 1, currentBalanceLong);
        // total expo to remove
        uint256 totalExpoToRemove = closeAmount * initialLongLeverage / 10 ** protocol.LEVERAGE_DECIMALS();
        // total expo to remove
        int256 longExpo = currentTotalExpo - int256(currentBalanceLong);
        // new long expo
        int256 newLongExpo =
            (currentTotalExpo - int256(totalExpoToRemove)) - (int256(currentBalanceLong) - int256(closeAmount));

        // expected imbalance percentage
        int256 imbalanceBps = (int256(initialVaultExpo) - newLongExpo) * int256(protocol.BPS_DIVISOR()) / longExpo;

        // call `i_imbalanceLimitClose` with totalExpoToRemove and closeAmount
        if (imbalanceBps >= protocol.getCloseExpoImbalanceLimit()) {
            // should revert with above close imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
            );
        }

        protocol.i_imbalanceLimitClose(totalExpoToRemove, closeAmount);
    }
}
