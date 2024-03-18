// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, DEPLOYER } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_imbalanceLimitDeposit` function in balanced state
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
     * @custom:scenario The `_imbalanceLimitDeposit` function should not revert when contract is balanced and position
     * is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitDeposit` function is called with a value below the deposit limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitDeposit() public view {
        (, uint256 vaultExpoValueToLimit) = _setupDeposit();
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit);
    }

    /**
     * @custom:scenario The `_imbalanceLimitDeposit` function should revert when long expo equal 0
     * @custom:given The initial long position is closed
     * @custom:and The protocol is imbalanced
     * @custom:when The `_imbalanceLimitDeposit` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitDepositZeroLongExpo() public {
        // disable close limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimitsBps(200, 200, 600, 0);

        // the initial tick
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

        // should revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        protocol.i_imbalanceLimitDeposit(0);
    }

    /**
     * @custom:scenario The `_imbalanceLimitDeposit` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitDeposit` function is called with a value above the deposit limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitDepositDisabled() public {
        (, uint256 vaultExpoValueToLimit) = _setupDeposit();

        // disable deposit limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimitsBps(200, 0, 600, 600);

        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario The `_imbalanceLimitDeposit` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitDeposit` function is called with a value above the deposit limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitDepositOutLimit() public {
        (uint256 imbalanceBps, uint256 vaultExpoValueToLimit) = _setupDeposit();
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
        );
        protocol.i_imbalanceLimitDeposit(vaultExpoValueToLimit + 1);
    }

    function _setupDeposit() private view returns (uint256 imbalanceBps_, uint256 vaultExpoValueToLimit_) {
        // current long expo
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        // initial deposit limit bps
        (, int256 depositLimit,,) = protocol.getExpoImbalanceLimitsBps();
        // imbalance bps
        imbalanceBps_ = uint256(depositLimit);
        // current vault expo value to imbalance the protocol
        vaultExpoValueToLimit_ = longExpo * imbalanceBps_ / protocol.BPS_DIVISOR();
    }
}
