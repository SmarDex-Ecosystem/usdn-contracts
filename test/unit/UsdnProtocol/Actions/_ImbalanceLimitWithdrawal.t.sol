// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_checkImbalanceLimitWithdrawal` function in balanced state
 */
contract TestExpoLimitsWithdrawal is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        // we enable only open limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 600, 0, -1);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitWithdrawal` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitWithdrawal` function is called with a value below the withdrawal limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitWithdrawal() public view {
        (, uint256 withdrawalValueToLimit) = _getWithdrawalLimitValues();
        protocol.i_checkImbalanceLimitWithdrawal(withdrawalValueToLimit, protocol.getTotalExpo());
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitWithdrawal` function should revert when vault expo equal 0
     * @custom:given The protocol has a zero vault balance / expo
     * @custom:when The `_checkImbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitWithdrawalZeroVaultExpo() public {
        protocol.emptyVault();
        uint256 totalExpo = protocol.getTotalExpo();

        // should revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidVaultExpo.selector);
        protocol.i_checkImbalanceLimitWithdrawal(0, totalExpo);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitWithdrawal` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitWithdrawalDisabled() public {
        (, uint256 withdrawalValueToLimit) = _getWithdrawalLimitValues();

        // disable withdrawal limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(200, 200, 0, 600, 300);

        protocol.i_checkImbalanceLimitWithdrawal(withdrawalValueToLimit + 1, protocol.getTotalExpo());
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitWithdrawal` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitWithdrawal` function is called with a value above the withdrawal limit
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitWithdrawalOutLimit() public {
        (int256 withdrawalLimitBps, uint256 withdrawalValueToLimit) = _getWithdrawalLimitValues();
        uint256 totalExpo = protocol.getTotalExpo();
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, withdrawalLimitBps)
        );

        protocol.i_checkImbalanceLimitWithdrawal(withdrawalValueToLimit + 1, totalExpo);
    }

    function _getWithdrawalLimitValues()
        private
        view
        returns (int256 withdrawalLimitBps_, uint256 withdrawalValueToLimit_)
    {
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();

        // withdrawal limit bps
        withdrawalLimitBps_ = protocol.getWithdrawalExpoImbalanceLimitBps();

        // the imbalance ratio: must be scaled for calculation
        uint256 scaledWithdrawalImbalanceRatio =
            FixedPointMathLib.divWad(uint256(withdrawalLimitBps_), protocol.BPS_DIVISOR());

        // vault expo value limit from current long expo: numerator and denominator
        // are at the same scale and result is rounded up
        uint256 vaultExpoValueLimit =
            FixedPointMathLib.divWadUp(longExpo, FixedPointMathLib.WAD + scaledWithdrawalImbalanceRatio);

        // withdrawal value to reach limit
        withdrawalValueToLimit_ = protocol.getBalanceVault() - vaultExpoValueLimit;
    }
}
