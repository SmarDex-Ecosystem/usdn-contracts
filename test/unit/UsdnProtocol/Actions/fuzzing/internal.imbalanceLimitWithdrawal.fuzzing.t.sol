// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitWithdrawal`
 * @custom:background Given a protocol instance in balanced state with random expos
 */
contract FuzzingImbalanceLimitWithdrawal is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitWithdrawal` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitWithdrawal(uint128 initialDeposit, uint128 initialLong, uint256 withdrawalAmount)
        public
    {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // range withdrawalAmount properly
        withdrawalAmount = bound(withdrawalAmount, 1, initialVaultExpo);
        // new vault expo
        uint256 newVaultExpo = initialVaultExpo - withdrawalAmount;
        // expected imbalance percentage
        int256 imbalancePct = (int256(uint256(initialLongExpo)) - int256(newVaultExpo)) * int256(protocol.BPS_DIVISOR())
            / int256(initialVaultExpo);

        // call `i_imbalanceLimitWithdrawal` with withdrawalAmount
        if (imbalancePct >= protocol.getHardLongExpoImbalanceLimit()) {
            // should revert with above hard long imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IUsdnProtocolErrors.UsdnProtocolHardLongImbalanceLimitReached.selector, imbalancePct
                )
            );
            protocol.i_imbalanceLimitWithdrawal(withdrawalAmount);
        } else {
            // should not revert
            protocol.i_imbalanceLimitWithdrawal(withdrawalAmount);
        }
    }
}
