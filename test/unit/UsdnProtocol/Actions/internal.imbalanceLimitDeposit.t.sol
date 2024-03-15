// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, DEPLOYER } from "test/utils/Constants.sol";

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
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitDeposit` function is called with a value inside limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitDeposit() public view {
        (, uint256 vaultExpoValueToLimit) = _getDepositValues();
        // call `imbalanceLimitDeposit` function with vaultExpoValueToLimit should not revert at the edge
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit);
    }

    /**
     * @custom:scenario The `imbalanceLimitDeposit` function should revert when long expo equal 0
     * @custom:given The initial long position is closed
     * @custom:and The protocol is imbalanced
     * @custom:when The `imbalanceLimitDeposit` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitDepositZeroLongExpo() public {
        // disable close limit
        vm.prank(ADMIN);
        protocol.setCloseExpoImbalanceLimit(0);

        // the initial tick
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

        // should revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        protocol.i_imbalanceLimitDeposit(0);
    }

    /**
     * @custom:scenario The `imbalanceLimitDeposit` function should not revert
     * when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitDeposit` function is called with a value above the deposit limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitDepositDisabled() public {
        (, uint256 vaultExpoValueToLimit) = _getDepositValues();

        // disable deposit limit
        vm.prank(ADMIN);
        protocol.setDepositExpoImbalanceLimit(0);

        // should not revert
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario The `imbalanceLimitDeposit` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitDeposit` function is called with a value above the deposit limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitDepositOutLimit() public {
        (uint256 imbalanceBps, uint256 vaultExpoValueToLimit) = _getDepositValues();
        // call `imbalanceLimitDeposit` function with vaultExpoValueToLimit + 1
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
        );
        // should revert
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    function _getDepositValues() private view returns (uint256 imbalanceBps_, uint256 vaultExpoValueToLimit_) {
        // current long expo
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getDepositExpoImbalanceLimit());
        // current vault expo value to imbalance the protocol
        vaultExpoValueToLimit_ = longExpo * imbalanceBps_ / protocol.BPS_DIVISOR();
    }
}
