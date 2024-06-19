// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";
import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { DEPLOYER } from "../../utils/Constants.sol";

import { IRebalancerEvents } from "../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerTypes } from "../../../src/interfaces/Rebalancer/IRebalancerTypes.sol";
import { ProtocolAction } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `initiateClosePosition` function of the rebalancer contract
 * @custom:background A rebalancer is set and the USDN protocol is initialized with the default params
 * The rebalancer was already triggered once and has an active position
 */
contract TestRebalancerInitiateClosePosition is
    UsdnProtocolBaseIntegrationFixture,
    IRebalancerEvents,
    IRebalancerTypes
{
    uint256 constant BASE_AMOUNT = 1000 ether;
    uint256 internal securityDepositValue;
    uint128 internal minAsset;
    uint128 internal amountInRebalancer;
    uint128 internal version;
    PositionData internal previousPositionData;

    function setUp() public {
        (, amountInRebalancer,,) = _setUpImbalanced();
        skip(5 minutes);

        vm.prank(DEPLOYER);

        minAsset = uint128(rebalancer.getMinAssetDeposit());

        mockPyth.setPrice(1280 ether / 1e10);
        mockPyth.setLastPublishTime(block.timestamp);

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);

        version = rebalancer.getPositionVersion();
        previousPositionData = rebalancer.getPositionData(version);
    }

    function test_setUp() external {
        assertGt(rebalancer.getPositionVersion(), 0, "The rebalancer version should be updated");
    }

    /**
     * @custom:scenario Closes partially a rebalancer amount
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function with a
     * portion of his rebalancer amount
     * @custom:then A `ClosePositionInitiated` event is emitted
     * @custom:and The user depositData is updated
     * @custom:and The position data is updated
     * @custom:and The user action is pending in protocol
     */
    function test_rebalancerInitiateClosePositionPartial() external {
        uint128 amount = amountInRebalancer / 10;

        uint256 amountToClose = FixedPointMathLib.fullMulDiv(
            amount,
            previousPositionData.entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(address(this)).entryPositionVersion)
                .entryAccMultiplier
        );

        vm.expectEmit();
        emit ClosePositionInitiated(address(this), amount, amountToClose, amountInRebalancer - amount);
        (bool success) = rebalancer.initiateClosePosition{ value: protocol.getSecurityDepositValue() }(
            amount, payable(address(this)), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "The rebalancer close should be successful");

        amountInRebalancer -= amount;

        UserDeposit memory depositData = rebalancer.getUserDepositData(address(this));

        assertEq(
            depositData.amount, amountInRebalancer, "The user's deposited amount in the rebalancer should be updated"
        );

        assertEq(
            depositData.entryPositionVersion,
            version,
            "The user's entry position's version in the rebalancer should be the same"
        );

        assertEq(
            rebalancer.getPositionData(version).amount + amountToClose,
            previousPositionData.amount,
            "The position data should be decreased"
        );

        assertEq(
            uint8(protocol.getUserPendingAction(address(this)).action),
            uint8(ProtocolAction.ValidateClosePosition),
            "The user protocol action should pending"
        );
    }

    /**
     * @custom:scenario Closes entirely a rebalancer amount
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function with his entire rebalancer amount
     * @custom:then A ClosePositionInitiated event is emitted
     * @custom:and The user depositData is deleted
     * @custom:and The position data is updated
     * @custom:and The user initiate close position is pending in protocol
     */
    function test_rebalancerInitiateClosePosition() external {
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
            amountInRebalancer, payable(address(this)), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );

        UserDeposit memory depositData = rebalancer.getUserDepositData(address(this));

        assertTrue(success, "The rebalancer close should be successful");
        assertEq(depositData.amount, 0, "The user's deposited amount in rebalancer should be zero");
        assertEq(depositData.entryPositionVersion, 0, "The user's entry position version should be zero");

        assertEq(
            rebalancer.getPositionData(version).amount + amountToClose,
            previousPositionData.amount,
            "The position data should be decreased"
        );

        assertEq(
            uint8(protocol.getUserPendingAction(address(this)).action),
            uint8(ProtocolAction.ValidateClosePosition),
            "The user protocol action should pending"
        );
    }

    /**
     * @custom:scenario The user sends too much ether when closing its position
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function with his deposited amount
     * @custom:and With too much ether
     * @custom:then The user gets back the excess ether sent
     */
    function test_rebalancerInitiateClosePositionRefundsExcessEther() external {
        vm.prank(DEPLOYER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0);

        uint256 securityDeposit = protocol.getSecurityDepositValue();
        uint256 userBalanceBefore = address(this).balance;
        uint256 excessAmount = 1 ether;

        // send more ether than necessary to trigger the refund
        rebalancer.initiateClosePosition{ value: securityDeposit + excessAmount }(
            amountInRebalancer, payable(address(this)), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );

        assertEq(payable(address(rebalancer)).balance, 0, "There should be no ether left in the rebalancer");
        assertEq(
            userBalanceBefore - securityDeposit, address(this).balance, "The overpaid amount should have been refunded"
        );
    }

    receive() external payable { }
}
