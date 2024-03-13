// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limit for `imbalanceLimitWithdrawal` function in balanced state
 */
contract TestExpoLimitsWithdrawal is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitWithdrawal` function is called with a value inside limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitWithdrawal() public view {
        (, uint256 longExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitWithdrawal` function with longExpoValueToLimit
        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitWithdrawal` function is called with a value above the hard long limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitWithdrawalOutLimit() public {
        (uint256 imbalanceBps, uint256 longExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitWithdrawal` function with vaultExpoValueToLimit + 1
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolHardLongImbalanceLimitReached.selector, imbalanceBps)
        );
        // should revert
        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit + 1);
    }

    function _testHelper() private view returns (uint256 imbalanceBps_, uint256 longExpoValueToLimit_) {
        uint256 vaultExpo_ = protocol.getBalanceVault();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getHardLongExpoImbalanceLimit());
        // current long expo value to imbalance the protocol
        longExpoValueToLimit_ = vaultExpo_ * imbalanceBps_ / protocol.BPS_DIVISOR();
    }
}
