// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limits for `imbalanceLimitWithdrawal` in balanced state
 */
contract TestUsdnProtocolExpoLimitsWithdrawal is UsdnProtocolBaseFixture {
    uint256 internal expos;

    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
        expos = protocol.getTotalExpo() - protocol.getBalanceLong();
        assertEq(expos, protocol.getBalanceVault(), "protocol not balanced");
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` should not revert when contract is
     * balanced and value inside limit
     * @custom:given The expo balanced protocol state
     * @custom:when The function is called with a value below the limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitWithdrawalInLimit() public view {
        protocol.i_imbalanceLimitWithdrawal(0.01 ether);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitWithdrawal` is called with a value above the hard long limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitWithdrawalOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getHardLongExpoImbalanceLimit());
        // current vault expo value to unbalance protocol
        uint256 vaultExpoValueToLimit = expos * imbalancePct / protocol.BPS_DIVISOR();
        // call `imbalanceLimitWithdrawal` with vaultExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitWithdrawal(vaultExpoValueToLimit);
        // call `imbalanceLimitWithdrawal` with vaultExpoValueToLimit + 1
        // should revert with the correct percentage
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolHardLongImbalanceLimitReached.selector, imbalancePct)
        );
        protocol.i_imbalanceLimitWithdrawal(vaultExpoValueToLimit + 1);
    }
}
