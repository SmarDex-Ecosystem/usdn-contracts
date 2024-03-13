// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limits for `imbalanceLimitDeposit` in balanced state
 */
contract TestUsdnProtocolExpoLimitsDeposit is UsdnProtocolBaseFixture {
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
     * @custom:scenario The `imbalanceLimitDeposit` should not revert when contract is
     * balanced and value inside limit
     * @custom:given The expo balanced protocol state
     * @custom:when The function is called with a value below the limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitDepositInLimit() public view {
        protocol.i_imbalanceLimitDeposit(0.01 ether);
    }

    /**
     * @custom:scenario The `imbalanceLimitDeposit` should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitDeposit` is called with a value above the soft vault limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitDepositOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getSoftVaultExpoImbalanceLimit());
        // current vault expo value to unbalance protocol
        uint256 vaultExpoValueToLimit = expos * imbalancePct / protocol.BPS_DIVISOR();
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
}
