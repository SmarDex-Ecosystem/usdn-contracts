// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol expo limit for `imbalanceLimitClose` function in a balanced state
 */
contract TestImbalanceLimitClose is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitClose` function is called with a value inside limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitClose() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitClose` function with totalExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitClose(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitClose` function is called with values above the vault hard limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitCloseOutLimit() public {
        (uint256 imbalanceBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _testHelper();
        // call `imbalanceLimitClose` function with totalExpoValueToLimit + 1
        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolHardVaultImbalanceLimitReached.selector, imbalanceBps
            )
        );
        // should revert
        protocol.i_imbalanceLimitClose(totalExpoValueToLimit + 1, longAmount);
    }

    function _testHelper()
        private
        view
        returns (uint256 imbalanceBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        // current long expo
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getCloseExpoImbalanceLimit());
        // current vault expo value for imbalance
        uint256 vaultExpoValueToLimit = longExpo * imbalanceBps_ / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and leverage
        longAmount_ =
            vaultExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
        // current total expo value to imbalance the protocol
        totalExpoValueToLimit_ = vaultExpoValueToLimit + longAmount_;
    }
}
