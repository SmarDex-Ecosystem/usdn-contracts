// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, DEPLOYER } from "test/utils/Constants.sol";

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
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseValues();
        // call `imbalanceLimitClose` function with totalExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitClose(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitClose` function is called with values above the close limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitCloseOutLimit() public {
        (uint256 imbalanceBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseValues();
        // call `imbalanceLimitClose` function with totalExpoValueToLimit + 1
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
        );
        // should revert
        protocol.i_imbalanceLimitClose(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` function should not revert
     * when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitClose` function is called with values above the close limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitCloseDisabled() public {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseValues();

        vm.prank(ADMIN);
        // disable limit
        protocol.setCloseExpoImbalanceLimit(0);

        // should not revert
        protocol.i_imbalanceLimitClose(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` function should revert when long expo equal 0
     * @custom:given The initial long positions is closed
     * @custom:and The protocol is imbalanced
     * @custom:when The `imbalanceLimitClose` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitCloseZeroLongExpo() public {
        // initial limit
        uint256 initialCloseExpoImbalanceLimit = uint256(protocol.getCloseExpoImbalanceLimitBps());

        // disable close limit
        vm.prank(ADMIN);
        protocol.setCloseExpoImbalanceLimit(0);

        // the initialized tick
        int24 tick = protocol.getMaxInitializedTick();

        vm.startPrank(DEPLOYER);

        // initiate close
        protocol.initiateClosePosition(
            tick,
            0, // no liquidation
            0, // unique long
            params.initialLong,
            abi.encode(params.initialPrice),
            abi.encode(params.initialPrice)
        );

        // wait more than 2 blocks
        skip(25);

        // validate close
        protocol.validateClosePosition(abi.encode(params.initialPrice), abi.encode(params.initialPrice));

        vm.stopPrank();

        // long expo should be equal 0
        assertEq(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo isn't 0");

        // reassign limit to activate verification
        vm.prank(ADMIN);
        protocol.setCloseExpoImbalanceLimit(initialCloseExpoImbalanceLimit);

        // should revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        protocol.i_imbalanceLimitClose(0, 0);
    }

    function _getCloseValues()
        private
        view
        returns (uint256 imbalanceBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        // current long expo
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getCloseExpoImbalanceLimitBps());
        // current vault expo value for imbalance
        uint256 vaultExpoValueToLimit = longExpo * imbalanceBps_ / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and leverage
        longAmount_ =
            vaultExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
        // current total expo value to imbalance the protocol
        totalExpoValueToLimit_ = vaultExpoValueToLimit + longAmount_;
    }
}
