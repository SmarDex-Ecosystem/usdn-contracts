// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { ADMIN, DEPLOYER } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_checkImbalanceLimitWithdrawal` function in balanced state
 */
contract TestExpoLimitsWithdrawal is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        // we enable only open limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 600, 0, 0, 0);
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
    function test_checkImbalanceLimitWithdrawalDisabled() public adminPrank {
        (, uint256 withdrawalValueToLimit) = _getWithdrawalLimitValues();

        // disable withdrawal limit
        protocol.setExpoImbalanceLimits(200, 200, 0, 600, 500, 300);

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

    /**
     * @custom:scenario Check withdrawal imbalance when there are pending withdrawals
     * @custom:given The protocol is in an unbalanced state due to pending withdrawals
     * @custom:when The `_checkImbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should revert with the expected imbalance
     */
    function test_RevertWhen_checkImbalanceLimitWithdrawalPendingVaultActions() public {
        (, uint256 withdrawalValueToLimit) = _getWithdrawalLimitValues();

        // temporarily disable limits to put the protocol in an unbalanced state
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        // this action will affect the vault trading expo once it's validated
        vm.startPrank(DEPLOYER);
        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint152(usdn.sharesOf(DEPLOYER) / 2),
            DEPLOYER,
            DEPLOYER,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        // restore limits
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 600, 0, 0, 0);

        uint256 totalExpo = protocol.getTotalExpo();
        int256 newVaultExpo =
            int256(protocol.getBalanceVault()) + protocol.getPendingBalanceVault() - int256(withdrawalValueToLimit);
        int256 expectedImbalance = (int256(totalExpo - protocol.getBalanceLong()) - newVaultExpo)
            * int256(protocol.BPS_DIVISOR()) / newVaultExpo;

        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, uint256(expectedImbalance)
            )
        );
        protocol.i_checkImbalanceLimitWithdrawal(withdrawalValueToLimit, totalExpo);
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
        int256 withdrawalValueToLimit =
            int256(protocol.getBalanceVault()) + protocol.getPendingBalanceVault() - int256(vaultExpoValueLimit);
        require(withdrawalValueToLimit > 0, "_ImbalanceLimitWithdrawal: withdrawal is not allowed");
        withdrawalValueToLimit_ = uint256(withdrawalValueToLimit);
    }
}
