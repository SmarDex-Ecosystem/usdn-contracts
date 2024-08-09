// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IUsdnProtocolErrors } from "../../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "../../utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitWithdrawal`
 * @custom:background Given a protocol instance in balanced state with random vault expo and long expo
 */
contract TestImbalanceLimitWithdrawalFuzzing is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` should pass on still balanced state
     * or revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitWithdrawal` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_checkImbalanceLimitWithdrawal(uint128 initialAmount, uint256 withdrawalAmount) public {
        // initialize random balanced protocol
        _randInitBalanced(initialAmount);
        uint256 vaultExpo = protocol.getBalanceVault();
        int256 currentLongExpo = int256(protocol.getTotalExpo() - protocol.getBalanceLong());
        // range withdrawalAmount properly
        withdrawalAmount = bound(withdrawalAmount, 1, uint256(vaultExpo));
        // new vault expo
        uint256 newVaultExpo = vaultExpo - withdrawalAmount;

        int256 imbalanceBps;
        if (newVaultExpo > 0) {
            // expected imbalance bps
            imbalanceBps =
                (currentLongExpo - int256(newVaultExpo)) * int256(protocol.BPS_DIVISOR()) / int256(newVaultExpo);
        }

        // initial withdrawal limit bps
        int256 withdrawalLimit = protocol.getWithdrawalExpoImbalanceLimitBps();

        uint256 totalExpo = protocol.getTotalExpo();
        if (newVaultExpo == 0) {
            // should revert because calculation is not possible
            vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidVaultExpo.selector);
        } else if (imbalanceBps >= withdrawalLimit) {
            // should revert with `imbalanceBps` withdrawal imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
            );
        }

        protocol.i_checkImbalanceLimitWithdrawal(withdrawalAmount, totalExpo);
    }
}
