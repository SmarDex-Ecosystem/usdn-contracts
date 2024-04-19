// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_checkImbalanceLimitWithdrawal` function in balanced state
 */
contract TestExpoLimitsWithdrawal is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.flags.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
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
     * @custom:given The protocol is balanced
     * @custom:and A long position is opened
     * @custom:and The price crashes very hard and liquidates the existing positions
     * @custom:and The vault balance/expo is 0
     * @custom:when The `_checkImbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitWithdrawalZeroVaultExpo() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 0.1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        // liquidate everything with huge bad debt
        protocol.liquidate(abi.encode(params.initialPrice / 100), 1);

        // vault expo should be zero
        assertEq(protocol.getBalanceVault(), 0, "vault expo isn't 0");
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
        protocol.setExpoImbalanceLimits(200, 200, 0, 600);

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
        (,, withdrawalLimitBps_,) = protocol.getExpoImbalanceLimits();

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
