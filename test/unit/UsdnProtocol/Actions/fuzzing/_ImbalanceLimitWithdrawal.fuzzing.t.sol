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
        uint256 vaultExpo = protocol.getBalanceVault();
        int256 currentLongExpo = int256(protocol.getTotalExpo() - protocol.getBalanceLong());
        // range withdrawalAmount properly
        withdrawalAmount = bound(withdrawalAmount, 1, uint256(vaultExpo));
        // new vault expo
        uint256 newVaultExpo = vaultExpo - withdrawalAmount;
        // expected imbalance bps
        int256 imbalanceBps =
            (currentLongExpo - int256(newVaultExpo)) * int256(protocol.BPS_DIVISOR()) / int256(vaultExpo);

        // initial withdrawal limit bps
        (,, int256 withdrawalLimit,) = protocol.getExpoImbalanceLimitsBps();

        uint256 totalExpo = protocol.getTotalExpo();
        // call `i_imbalanceLimitWithdrawal` with withdrawalAmount
        if (imbalanceBps >= withdrawalLimit) {
            // should revert with above withdrawal imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
            );
        }

        protocol.i_imbalanceLimitWithdrawal(withdrawalAmount, totalExpo);
    }
}
