// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, DEPLOYER } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_checkImbalanceLimitClose` function in a balanced state
 */
contract TestImbalanceLimitClose is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.flags.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitClose` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitClose` function is called with a value below the close limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitClose() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues();
        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitClose` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitClose` function is called with values above the close limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_checkImbalanceLimitCloseOutLimit() public {
        (int256 closeLimitBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues();
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, closeLimitBps)
        );
        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitClose` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitClose` function is called with values above the close limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitCloseDisabled() public {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues();

        vm.prank(ADMIN);
        // disable limit
        protocol.setExpoImbalanceLimits(200, 200, 600, 0);

        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitClose` function should revert when long expo equal 0
     * @custom:given The initial long positions is closed
     * @custom:and The protocol is imbalanced
     * @custom:when The `_checkImbalanceLimitClose` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWith_checkImbalanceLimitCloseZeroLongExpo() public {
        // initial limit
        (,,, int256 initialCloseLimit) = protocol.getExpoImbalanceLimits();

        // disable limits
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0);

        // the initialized tick
        int24 tick = protocol.getMaxInitializedTick();

        vm.startPrank(DEPLOYER);

        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(params.initialPrice);

        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: new uint128[](1) });

        // initiate close
        protocol.initiateClosePosition(
            tick,
            0, // no liquidation
            0, // unique long
            params.initialLong,
            abi.encode(params.initialPrice),
            data
        );

        // wait more than 2 blocks
        _waitDelay();

        // validate close
        protocol.validateClosePosition(abi.encode(params.initialPrice), data);

        vm.stopPrank();

        // long expo should be equal 0
        assertEq(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo isn't 0");

        // reassign limit to activate verification
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 0, uint256(initialCloseLimit));

        // should revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        protocol.i_checkImbalanceLimitClose(0, 0);
    }

    function _getCloseLimitValues()
        private
        view
        returns (int256 closeLimitBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        // current long expo
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // close limit bps
        (,,, closeLimitBps_) = protocol.getExpoImbalanceLimits();
        // current vault expo value for imbalance
        uint256 vaultExpoValueToLimit = longExpo * uint256(closeLimitBps_) / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and any leverage
        longAmount_ =
            vaultExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
        // current total expo value to imbalance the protocol
        totalExpoValueToLimit_ = vaultExpoValueToLimit + longAmount_;
    }
}
