// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limits for `imbalanceLimitClose` in balanced state
 */
contract TestUsdnProtocolExpoLimitsClose is UsdnProtocolBaseFixture {
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
     * @custom:scenario The `imbalanceLimitClose` should not revert when contract is balanced and value bellow the limit
     * @custom:given The expo balanced protocol state
     * @custom:when The function is called with values below the limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitCloseInLimit() public view {
        protocol.i_imbalanceLimitClose(0.02 ether, 0.01 ether);
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitClose` is called with values above the vault hard limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitCloseOutLimit() public {
        // imbalance percentage limit
        uint256 imbalancePct = uint256(protocol.getHardVaultExpoImbalanceLimit());
        // current long expo value for imbalance
        uint256 vaultExpoValueToLimit =
            expos * uint256(protocol.getHardVaultExpoImbalanceLimit()) / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and leverage
        uint256 longAmount =
            vaultExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
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
