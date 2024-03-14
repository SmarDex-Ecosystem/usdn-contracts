// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitDeposit`
 * @custom:background Given a protocol instance in balanced state with random expos
 */
contract FuzzingImbalanceLimitDeposit is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitDeposit` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
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
        int256 newExpoVault = int256(initialVaultExpo + depositAmount);
        // expected imbalance percentage
        int256 imbalancePct = (newExpoVault - int256(uint256(initialLongExpo))) * int256(protocol.BPS_DIVISOR())
            / int256(uint256(initialLongExpo));

        // call `imbalanceLimitDeposit` with depositAmount
        if (imbalancePct >= protocol.getSoftVaultExpoImbalanceLimit()) {
            // should revert with above soft vault imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IUsdnProtocolErrors.UsdnProtocolSoftVaultImbalanceLimitReached.selector, imbalancePct
                )
            );
        }

        protocol.i_imbalanceLimitDeposit(depositAmount);
    }
}
