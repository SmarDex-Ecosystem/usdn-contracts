// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitOpen`
 * @custom:background Given a protocol instance in balanced state with random expos
 */
contract FuzzingImbalanceLimitOpen is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitOpen` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitOpen` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitOpen(uint128 initialDeposit, uint128 initialLong, uint256 openAmount) public {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // range withdrawalAmount properly
        openAmount = bound(openAmount, 1, type(uint128).max);
        // total expo to add
        uint256 totalExpoToAdd = openAmount * initialLongLeverage / 10 ** protocol.LEVERAGE_DECIMALS();
        // expected imbalance percentage
        int256 imbalanceBps = (
            (int256(protocol.getTotalExpo() + totalExpoToAdd) - int256(protocol.getBalanceLong() + openAmount))
                - int256(initialVaultExpo)
        ) * int256(protocol.BPS_DIVISOR()) / int256(initialVaultExpo);
        // call `i_imbalanceLimitWithdrawal` with withdrawalAmount
        if (imbalanceBps >= protocol.getOpenExpoImbalanceLimit()) {
            // should revert with above open imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IUsdnProtocolErrors.UsdnProtocolSoftLongImbalanceLimitReached.selector, imbalanceBps
                )
            );
        }

        protocol.i_imbalanceLimitOpen(totalExpoToAdd, openAmount);
    }
}
