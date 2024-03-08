// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test internal functions of the protocol expo limits in balanced state and positions above limits
 */
contract TestUsdnProtocolExpoAboveLimits is UsdnProtocolBaseFixture {
    uint256 internal expos;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        expos = protocol.getTotalExpo() - protocol.getBalanceLong();
        assertEq(expos, protocol.getBalanceVault(), "protocol not balanced");
    }

    /**
     * @custom:scenario The `imbalanceLimitDeposit` should revert when contract is balanced
     * and position value unbalance
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitDeposit` is called with a value above the soft vault limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitDepositOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getSoftVaultExpoImbalanceLimit());
        // current vault expo value to unbalance protocol
        uint256 vaultExpoValueToLimit = expos * imbalancePct / uint256(protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR());
        // call `imbalanceLimitDeposit` with vaultExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit);
        // call `imbalanceLimitDeposit` with vaultExpoValueToLimit + 1
        // should revert with the correct percentage
        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolSoftVaultImbalanceLimitReached.selector, imbalancePct
            )
        );
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` should revert when contract is balanced
     * and position value unbalance
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitWithdrawal` is called with a value above the hard long limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitWithdrawalOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getHardLongExpoImbalanceLimit());
        // current vault expo value to unbalance protocol
        uint256 vaultExpoValueToLimit = expos * imbalancePct / uint256(protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR());
        // call `imbalanceLimitWithdrawal` with vaultExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitWithdrawal(vaultExpoValueToLimit);
        // call `imbalanceLimitWithdrawal` with vaultExpoValueToLimit + 1
        // should revert with the correct percentage
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolHardLongImbalanceLimitReached.selector, imbalancePct)
        );
        protocol.i_imbalanceLimitWithdrawal(vaultExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario The `imbalanceLimitOpen` should revert when contract is balanced
     * and position value unbalance
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitOpen` is called with values above the soft long limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitOpenOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getSoftLongExpoImbalanceLimit());
        // current long expo value to unbalance protocol
        uint256 vaultExpoValueToLimit = expos * imbalancePct / uint256(protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR());
        // long amount for vaultExpoValueToLimit and leverage
        uint256 longAmount = FixedPointMathLib.fullMulDiv(
            vaultExpoValueToLimit, 10 ** protocol.LEVERAGE_DECIMALS(), protocol.i_getLeverage(2000 ether, 1500 ether)
        );
        // current total expo value to unbalance protocol
        uint256 totalExpoValueToLimit = vaultExpoValueToLimit + longAmount;
        // call `imbalanceLimitOpen` with totalExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitOpen(totalExpoValueToLimit, longAmount);
        // call `imbalanceLimitOpen` with totalExpoValueToLimit + 1
        // should revert with the correct percentage
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolSoftLongImbalanceLimitReached.selector, imbalancePct)
        );
        protocol.i_imbalanceLimitOpen(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` should revert when contract is balanced
     * and position value unbalance
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitClose` is called with values above the vault hard limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitCloseOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getHardVaultExpoImbalanceLimit());
        // current long expo value for imbalance
        uint256 vaultExpoValueToLimit = expos * uint256(protocol.getHardVaultExpoImbalanceLimit())
            / uint256(protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR());
        // long amount for vaultExpoValueToLimit and leverage
        uint256 longAmount = FixedPointMathLib.fullMulDiv(
            vaultExpoValueToLimit, 10 ** protocol.LEVERAGE_DECIMALS(), protocol.i_getLeverage(2000 ether, 1500 ether)
        );
        // current total expo value to imbalance
        uint256 totalExpoValueToLimit = vaultExpoValueToLimit + longAmount;
        // call `imbalanceLimitClose` with totalExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitClose(totalExpoValueToLimit, longAmount);
        // call `imbalanceLimitClose` with totalExpoValueToLimit + 1
        // should revert with the correct percentage
        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolHardVaultImbalanceLimitReached.selector, imbalancePct
            )
        );
        protocol.i_imbalanceLimitClose(totalExpoValueToLimit + 1, longAmount);
    }
}
