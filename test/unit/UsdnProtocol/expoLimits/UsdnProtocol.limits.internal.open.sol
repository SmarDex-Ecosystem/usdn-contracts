// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limits for `imbalanceLimitOpen` in balanced state
 */
contract TestUsdnProtocolExpoLimitsOpen is UsdnProtocolBaseFixture {
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
     * @custom:scenario The `imbalanceLimitOpen` should not revert when contract is balanced and value bellow the limit
     * @custom:given The expo balanced protocol state
     * @custom:when The function is called with values below the limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitOpenInLimit() public view {
        protocol.i_imbalanceLimitOpen(0.02 ether, 0.01 ether);
    }

    /**
     * @custom:scenario The `imbalanceLimitOpen` should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitOpen` is called with values above the soft long limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitOpenOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getSoftLongExpoImbalanceLimit());
        // current long expo value to unbalance protocol
        uint256 vaultExpoValueToLimit = expos * imbalancePct / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and leverage
        uint256 longAmount =
            vaultExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
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
}
