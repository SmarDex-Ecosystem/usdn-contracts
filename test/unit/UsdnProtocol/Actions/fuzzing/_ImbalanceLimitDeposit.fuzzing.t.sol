// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitDeposit`
 * @custom:background Given a protocol instance in balanced state with random vault expo and long expo
 */
contract FuzzingImbalanceLimitDeposit is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitDeposit` should pass on still balanced state
     * or revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitDeposit` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitDeposit(uint128 initialDeposit, uint128 initialLong, uint256 depositAmount)
        public
    {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // range depositAmount properly
        depositAmount = bound(depositAmount, 1, type(uint128).max);
        // new vault expo
        int256 newExpoVault = int256(uint256(params.initialDeposit) + depositAmount);
        // initialLongExpo
        uint256 initialLongExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // expected imbalance bps
        int256 imbalanceBps =
            (newExpoVault - int256(initialLongExpo)) * int256(protocol.BPS_DIVISOR()) / int256(initialLongExpo);

        // initial deposit limit bps
        (, int256 depositLimit,,) = protocol.getExpoImbalanceLimitsBps();
        // call `imbalanceLimitDeposit` with depositAmount
        if (imbalanceBps >= depositLimit) {
            // should revert with above deposit imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
            );
        }

        protocol.i_imbalanceLimitDeposit(depositAmount);
    }
}
