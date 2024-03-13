// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limit for `imbalanceLimitDeposit` function in balanced state
 */
contract TestImbalanceLimitDeposit is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `imbalanceLimitDeposit` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitDeposit` function is called with a value inside limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitDeposit() public view {
        (, uint256 vaultExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitDeposit` with vaultExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit);
    }

    /**
     * @custom:scenario The `imbalanceLimitDeposit` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The expo balanced protocol state
     * @custom:when The `imbalanceLimitDeposit` function is called with a value above the soft vault limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitDepositOutLimit() public {
        (uint256 imbalanceBps, uint256 vaultExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitDeposit` function with vaultExpoValueToLimit + 1
        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolSoftVaultImbalanceLimitReached.selector, imbalanceBps
            )
        );
        // should revert
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    function _testHelper() private view returns (uint256 imbalanceBps_, uint256 vaultExpoValueToLimit_) {
        // current long expo
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getSoftVaultExpoImbalanceLimit());
        // current vault expo value to imbalance the protocol
        vaultExpoValueToLimit_ = longExpo * imbalanceBps_ / protocol.BPS_DIVISOR();
    }
}
