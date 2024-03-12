// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test internal functions of the protocol expo limits in balanced state and positions in range
 */
contract TestUsdnProtocolExpoBellowLimits is UsdnProtocolBaseFixture {
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
     * @custom:scenario The `imbalanceLimitDeposit` should not revert when contract is balanced and value bellow the
     * limit
     * @custom:given The expo balanced protocol state
     * @custom:when The function is called with a value below the limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitDepositInLimit() public view {
        protocol.i_imbalanceLimitDeposit(0.01 ether);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` should not revert when contract is balanced and value bellow the
     * limit
     * @custom:given The expo balanced protocol state
     * @custom:when The function is called with a value below the limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitWithdrawalInLimit() public view {
        protocol.i_imbalanceLimitWithdrawal(0.01 ether);
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
     * @custom:scenario The `imbalanceLimitClose` should not revert when contract is balanced and value bellow the limit
     * @custom:given The expo balanced protocol state
     * @custom:when The function is called with values below the limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitCloseInLimit() public view {
        protocol.i_imbalanceLimitClose(0.02 ether, 0.01 ether);
    }
}
