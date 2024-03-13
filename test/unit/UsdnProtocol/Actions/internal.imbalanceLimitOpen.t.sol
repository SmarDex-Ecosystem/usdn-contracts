// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limit for `imbalanceLimitOpen` function in balanced state
 */
contract TestExpoLimitsOpen is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `imbalanceLimitOpen` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitOpen` function is called with a value inside limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitOpen() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitOpen` function with totalExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitOpen(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The `imbalanceLimitOpen` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitOpen` function is called with values above the soft long limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitOpenOutLimit() public {
        (uint256 imbalanceBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitOpen` function with totalExpoValueToLimit + 1
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolSoftLongImbalanceLimitReached.selector, imbalanceBps)
        );
        // should revert
        protocol.i_imbalanceLimitOpen(totalExpoValueToLimit + 1, longAmount);
    }

    function _testHelper()
        private
        view
        returns (uint256 imbalanceBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        // current vault expo
        uint256 vaultExpo = protocol.getBalanceVault();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getSoftLongExpoImbalanceLimit());
        // current long expo value to unbalance protocol
        uint256 longExpoValueToLimit = vaultExpo * imbalanceBps_ / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and leverage
        longAmount_ =
            longExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
        // current total expo value to imbalance the protocol
        totalExpoValueToLimit_ = longExpoValueToLimit + longAmount_;
    }
}
