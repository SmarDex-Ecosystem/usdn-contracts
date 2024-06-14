// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import {
    PreviousActionsData,
    PositionId,
    ProtocolAction
} from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { ADMIN, DEPLOYER, USER_1 } from "../../../utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_checkImbalanceLimitDeposit` function in balanced state
 */
contract TestImbalanceLimitDeposit is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        // we enable only deposit limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 200, 0, 0, 0);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitDeposit` function should not revert when contract is balanced and
     * position
     * is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitDeposit` function is called with a value below the deposit limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitDeposit() public view {
        (, uint256 vaultExpoValueToLimit) = _getDepositLimitValues();
        protocol.i_checkImbalanceLimitDeposit(vaultExpoValueToLimit);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitDeposit` function should revert when long expo equal 0
     * @custom:given The initial long position is closed
     * @custom:and The protocol is imbalanced
     * @custom:when The `_checkImbalanceLimitDeposit` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitDepositZeroLongExpo() public {
        // disable close limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(200, 200, 600, 0, 0);

        // the initial tick
        int24 tick = protocol.getHighestPopulatedTick();

        vm.startPrank(DEPLOYER);

        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(params.initialPrice);

        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: new uint128[](1) });

        // initiate close
        protocol.initiateClosePosition(
            PositionId(tick, 0, 0), params.initialLong, DEPLOYER, DEPLOYER, abi.encode(params.initialPrice), data
        );

        // wait more than 2 blocks
        _waitDelay();

        // validate close
        protocol.validateClosePosition(DEPLOYER, abi.encode(params.initialPrice), data);

        vm.stopPrank();

        // long expo should be equal 0
        assertEq(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo isn't 0");

        // should revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        protocol.i_checkImbalanceLimitDeposit(0);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitDeposit` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitDeposit` function is called with a value above the deposit limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitDepositDisabled() public {
        (, uint256 vaultExpoValueToLimit) = _getDepositLimitValues();

        // disable deposit limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(200, 0, 600, 600, 300);

        protocol.i_checkImbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitDeposit` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitDeposit` function is called with a value above the deposit limit
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitDepositOutLimit() public {
        (int256 depositLimitBps, uint256 vaultExpoValueToLimit) = _getDepositLimitValues();
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, depositLimitBps)
        );
        protocol.i_checkImbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario Check deposit imbalance when there are pending deposits
     * @custom:given The protocol is in an unbalanced state due to pending deposits
     * @custom:when The `_checkImbalanceLimitDeposit` function is called
     * @custom:then The transaction should revert with the expected imbalance
     */
    function test_RevertWhen_checkImbalanceLimitDepositPendingVaultActions() public {
        (, uint256 vaultExpoValueToLimit) = _getDepositLimitValues();

        // temporarily disable limits to put the protocol in an unbalanced state
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0);
        // this action will affect the vault trading expo once it's validated
        setUpUserPositionInVault(USER_1, ProtocolAction.InitiateDeposit, params.initialDeposit, params.initialPrice);
        // restore limits
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 200, 0, 0, 0);

        int256 newVaultExpo =
            int256(protocol.getBalanceVault() + vaultExpoValueToLimit) + protocol.getPendingBalanceVault();
        int256 currentLongExpo = int256(protocol.getTotalExpo() - protocol.getBalanceLong());
        int256 expectedImbalance = (newVaultExpo - currentLongExpo) * int256(protocol.BPS_DIVISOR()) / currentLongExpo;

        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, uint256(expectedImbalance)
            )
        );
        protocol.i_checkImbalanceLimitDeposit(vaultExpoValueToLimit);
    }

    function _getDepositLimitValues() private view returns (int256 depositLimitBps_, uint256 vaultExpoValueToLimit_) {
        // current long expo
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // deposit limit bps
        depositLimitBps_ = protocol.getDepositExpoImbalanceLimitBps();
        // current vault expo value to imbalance the protocol
        int256 vaultExpoValueToLimit = int256(longExpo * uint256(depositLimitBps_) / protocol.BPS_DIVISOR());
        vaultExpoValueToLimit -= protocol.getPendingBalanceVault();
        require(vaultExpoValueToLimit > 0, "_ImbalanceLimitDeposit: deposit is not allowed");
        vaultExpoValueToLimit_ = uint256(vaultExpoValueToLimit);
    }
}
