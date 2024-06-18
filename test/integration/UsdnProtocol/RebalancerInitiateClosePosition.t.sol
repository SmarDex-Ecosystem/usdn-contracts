// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";
import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { DEPLOYER } from "../../utils/Constants.sol";

import { IRebalancerEvents } from "../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { PositionId, ProtocolAction, TickData } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IRebalancerErrors } from "../../../src/interfaces/Rebalancer/IRebalancerErrors.sol";

/**
 * @custom:feature The `initiateClosePosition` function of the rebalancer contract
 * @custom:background A rebalancer is set and the USDN protocol is initialized with the default params
 */
contract UsdnProtocolRebalancerInitiateClosePosition is UsdnProtocolBaseIntegrationFixture, IRebalancerEvents {
    uint256 constant BASE_AMOUNT = 1000 ether;
    uint256 internal securityDepositValue;
    uint128 internal minAsset;
    uint128 internal amountInRebalancer;
    int24 internal tickSpacing;

    PositionId internal posToLiquidate;
    TickData internal tickToLiquidateData;

    function setUp() public {
        (tickSpacing, amountInRebalancer, posToLiquidate, tickToLiquidateData) = _setUpImbalanced();
        skip(5 minutes);

        vm.prank(DEPLOYER);
        protocol.setExpoImbalanceLimits(
            uint256(defaultLimits.depositExpoImbalanceLimitBps),
            uint256(defaultLimits.withdrawalExpoImbalanceLimitBps),
            uint256(defaultLimits.openExpoImbalanceLimitBps),
            uint256(defaultLimits.closeExpoImbalanceLimitBps),
            550
        );

        minAsset = uint128(rebalancer.getMinAssetDeposit());

        mockPyth.setPrice(1280 ether / 1e10);
        mockPyth.setLastPublishTime(block.timestamp);
        assertEq(rebalancer.getPositionVersion(), 0, "The rebalancer version should be 0");

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);

        assertGt(rebalancer.getPositionVersion(), 0, "The rebalancer version should be updated");
    }

    /**
     * @custom:scenario The user partially closes its position with a remaining amount lower than `_minAssetDeposit`
     * @custom:given A rebalancer long position opened in the USDN Protocol
     * @custom:and A user having deposited assets in the rebalancer before the first trigger
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function
     * @custom:then The transaction should revert with a `RebalancerInvalidAmount` error
     */
    function test_RevertWhen_RebalancerInvalidAmount() external {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAmount.selector);
        rebalancer.initiateClosePosition(
            amountInRebalancer - minAsset + 1, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user partially closes his deposited amount
     * @custom:given A rebalancer long position opened in the USDN Protocol
     * @custom:and A user having deposited assets in the rebalancer before the first trigger
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function
     * @custom:then A `ClosePositionInitiated` is emitted
     * @custom:and The user depositData is updated
     */
    function test_RebalancerInitiateClosePositionPartial() external {
        uint128 amount = amountInRebalancer / 10;

        uint256 amountToClose = FixedPointMathLib.fullMulDiv(
            amount,
            rebalancer.getPositionData(rebalancer.getPositionVersion()).entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(address(this)).entryPositionVersion)
                .entryAccMultiplier
        );
        vm.expectEmit();
        emit ClosePositionInitiated(address(this), amount, amountToClose, amountInRebalancer - amount);
        (bool success) = rebalancer.initiateClosePosition{ value: protocol.getSecurityDepositValue() }(
            amount, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "The rebalancer close should be successful");

        amountInRebalancer -= amount;

        assertEq(
            rebalancer.getUserDepositData(address(this)).amount,
            amountInRebalancer,
            "The user's deposited amount in the rebalancer should be updated"
        );
        assertEq(
            rebalancer.getUserDepositData(address(this)).entryPositionVersion,
            rebalancer.getPositionVersion(),
            "The user's entry position's version in the rebalancer should be the same"
        );
    }

    /**
     * @custom:scenario The user closes his position fully
     * @custom:given A rebalancer long position opened in the USDN Protocol
     * @custom:and A user having deposited assets in the rebalancer before the first trigger
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function
     * @custom:then A ClosePositionInitiated event is emitted
     * @custom:and The user depositData is deleted
     */
    function test_RebalancerInitiateClosePosition() external {
        vm.prank(DEPLOYER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0);

        uint256 amountToClose = FixedPointMathLib.fullMulDiv(
            amountInRebalancer,
            rebalancer.getPositionData(rebalancer.getPositionVersion()).entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(address(this)).entryPositionVersion)
                .entryAccMultiplier
        );

        vm.expectEmit();
        emit ClosePositionInitiated(address(this), amountInRebalancer, amountToClose, 0);
        (bool success) = rebalancer.initiateClosePosition{ value: protocol.getSecurityDepositValue() }(
            amountInRebalancer, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "The rebalancer close should be successful");

        assertEq(
            rebalancer.getUserDepositData(address(this)).amount,
            0,
            "The user's deposited amount in rebalancer should be zero"
        );
        assertEq(
            rebalancer.getUserDepositData(address(this)).entryPositionVersion,
            0,
            "The user's entry position version should be zero"
        );
    }

    receive() external payable { }
}
