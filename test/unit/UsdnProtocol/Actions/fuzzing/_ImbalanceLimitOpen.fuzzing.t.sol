// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IUsdnProtocolErrors } from "../../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolBaseFixture } from "../../utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests of the protocol expo limit for internal `imbalanceLimitOpen`
 * @custom:background Given a protocol instance in balanced state with random vault expo and long expo
 */
contract TestImbalanceLimitOpenFuzzing is UsdnProtocolBaseFixture {
    /**
     * @custom:scenario The `imbalanceLimitOpen` should pass on still balanced state
     * or revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitOpen` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_checkImbalanceLimitOpen(uint128 initialAmount, uint256 openAmount, uint256 leverage) public {
        // initialize random balanced protocol
        _randInitBalanced(initialAmount);

        (uint256 minLeverage, uint256 maxLeverage,) = protocol.getEdgePositionValues();

        leverage = bound(leverage, minLeverage, maxLeverage);
        // range withdrawalAmount properly
        openAmount = bound(openAmount, 1, type(uint128).max);
        // total expo to add
        uint256 totalExpoToAdd = openAmount * leverage / 10 ** Constants.LEVERAGE_DECIMALS;

        int256 vaultExpo = int256(protocol.getBalanceVault());
        // expected imbalance bps
        int256 imbalanceBps = (
            (int256(protocol.getTotalExpo() + totalExpoToAdd) - int256(protocol.getBalanceLong() + openAmount))
                - vaultExpo
        ) * int256(Constants.BPS_DIVISOR) / vaultExpo;

        // initial open limit bps
        int256 openLimit = initialLimits.openExpoImbalanceLimit;

        if (imbalanceBps >= openLimit) {
            // should revert with above open imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
            );
        }

        protocol.i_checkImbalanceLimitOpen(totalExpoToAdd, openAmount);
    }
}
