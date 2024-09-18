// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { DEPLOYER, USER_1 } from "../../utils/Constants.sol";
import { SET_PROTOCOL_PARAMS_MANAGER } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IRebalancerErrors } from "../../../src/interfaces/Rebalancer/IRebalancerErrors.sol";
import { IRebalancerEvents } from "../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerTypes } from "../../../src/interfaces/Rebalancer/IRebalancerTypes.sol";

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
    uint88 internal amountInRebalancer;
    uint128 internal version;
    PositionData internal previousPositionData;
    PositionId internal prevPosId;
    Position internal protocolPosition;
    uint128 internal wstEthPrice;

    function setUp() public {
        (, amountInRebalancer,,) = _setUpImbalanced(15 ether);
        uint256 maxLeverage = protocol.getMaxLeverage();
        vm.prank(DEPLOYER);
        rebalancer.setPositionMaxLeverage(maxLeverage);
        skip(5 minutes);

        {
            wstEthPrice = 1490 ether;
            uint128 ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice)) / 1e10;
            mockPyth.setPrice(int64(uint64(ethPrice)));
            mockPyth.setLastPublishTime(block.timestamp);
            wstEthPrice = uint128(wstETH.getStETHByWstETH(ethPrice * 1e10));
        }

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);

        version = rebalancer.getPositionVersion();
        previousPositionData = rebalancer.getPositionData(version);
        prevPosId = PositionId({
            tick: previousPositionData.tick,
            tickVersion: previousPositionData.tickVersion,
            index: previousPositionData.index
        });
        (protocolPosition,) = protocol.getLongPosition(prevPosId);
    }

    function test_setUp() public view {
        assertGt(rebalancer.getPositionVersion(), 0, "The rebalancer version should be updated");
        assertGt(protocolPosition.amount - previousPositionData.amount, 0, "The protocol bonus should be positive");
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
    function test_rebalancerInitiateClosePositionPartial() public {
        // choose an amount small enough to not trigger imbalance limits
        uint88 amount = amountInRebalancer / 100;

        uint256 amountToCloseWithoutBonus = FixedPointMathLib.fullMulDiv(
            amount,
            previousPositionData.entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(address(this)).entryPositionVersion)
                .entryAccMultiplier
        );

        uint256 amountToClose = amountToCloseWithoutBonus
            + amountToCloseWithoutBonus * (protocolPosition.amount - previousPositionData.amount)
                / previousPositionData.amount;

        vm.expectEmit();
        emit ClosePositionInitiated(address(this), amount, amountToClose, amountInRebalancer - amount);
        (bool success) = rebalancer.initiateClosePosition{ value: protocol.getSecurityDepositValue() }(
            amount, address(this), DISABLE_MIN_PRICE, "", EMPTY_PREVIOUS_DATA
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
            rebalancer.getPositionData(version).amount + amountToCloseWithoutBonus,
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
     * @custom:scenario The close would push the imbalance above the limit for the rebalancer
     * @custom:when The user wants to close with an amount that imbalance the protocol too much
     * @custom:then The call reverts with a UsdnProtocolImbalanceLimitReached error
     */
    function test_RevertWhen_rebalancerInitiateClosePositionPartialTriggerImbalanceLimit() public {
        // choose an amount big enough to trigger imbalance limits
        uint88 amount = amountInRebalancer / 10;
        uint256 securityDeposit = protocol.getSecurityDepositValue();

        int256 currentVaultExpo = int256(protocol.getBalanceVault()) + protocol.getPendingBalanceVault();
        int256 newLongExpo = int256(protocol.getTotalExpo() - protocolPosition.totalExpo / 10)
            - (
                int256(protocol.getBalanceLong())
                    - protocol.getPositionValue(prevPosId, wstEthPrice, uint128(block.timestamp)) / 10
            );
        int256 expectedImbalance = (currentVaultExpo - newLongExpo) * int256(BPS_DIVISOR) / newLongExpo;

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolImbalanceLimitReached.selector, expectedImbalance));
        rebalancer.initiateClosePosition{ value: securityDeposit }(
            amount, address(this), DISABLE_MIN_PRICE, "", EMPTY_PREVIOUS_DATA
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
    function test_rebalancerInitiateClosePosition() public {
        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        uint256 amountToCloseWithoutBonus = FixedPointMathLib.fullMulDiv(
            amountInRebalancer,
            rebalancer.getPositionData(rebalancer.getPositionVersion()).entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(address(this)).entryPositionVersion)
                .entryAccMultiplier
        );

        uint256 amountToClose = amountToCloseWithoutBonus
            + amountToCloseWithoutBonus * (protocolPosition.amount - previousPositionData.amount)
                / previousPositionData.amount;

        vm.expectEmit();
        emit ClosePositionInitiated(address(this), amountInRebalancer, amountToClose, 0);
        (bool success) = rebalancer.initiateClosePosition{ value: protocol.getSecurityDepositValue() }(
            amountInRebalancer, address(this), DISABLE_MIN_PRICE, "", EMPTY_PREVIOUS_DATA
        );

        UserDeposit memory depositData = rebalancer.getUserDepositData(address(this));

        assertTrue(success, "The rebalancer close should be successful");
        assertEq(depositData.amount, 0, "The user's deposited amount in rebalancer should be zero");
        assertEq(depositData.entryPositionVersion, 0, "The user's entry position version should be zero");

        assertEq(
            rebalancer.getPositionData(version).amount + amountToCloseWithoutBonus,
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
     * @custom:when The user calls the rebalancer's {initiateClosePosition} function with too much ether
     * @custom:then The user gets back the excess ether sent
     */
    function test_rebalancerInitiateClosePositionRefundsExcessEther() public {
        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        uint256 securityDeposit = protocol.getSecurityDepositValue();
        uint256 userBalanceBefore = address(this).balance;
        uint256 excessAmount = 1 ether;

        // send more ether than necessary to trigger the refund
        rebalancer.initiateClosePosition{ value: securityDeposit + excessAmount }(
            amountInRebalancer, address(this), DISABLE_MIN_PRICE, "", EMPTY_PREVIOUS_DATA
        );

        assertEq(payable(rebalancer).balance, 0, "There should be no ether left in the rebalancer");
        assertEq(
            userBalanceBefore - securityDeposit, address(this).balance, "The overpaid amount should have been refunded"
        );
    }

    /**
     * @custom:scenario Call `initiateClosePosition` function after the rebalancer is liquidated
     * @custom:given The rebalancer's position got liquidated
     * @custom:and Another user deposits in the rebalancer
     * @custom:and The rebalancer is triggered again
     * @custom:when The `initiateClosePosition` function is called by the user in the liquidated version
     * @custom:then It should revert with `RebalancerUserLiquidated` error
     */
    function test_RevertWhen_rebalancerUserLiquidated() public {
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        // compensate imbalance to allow rebalancer users to close
        (, PositionId memory newPosId) = protocol.initiateOpenPosition{ value: securityDeposit }(
            20 ether,
            1100 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            payable(address(this)),
            payable(address(this)),
            NO_PERMIT2,
            "",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateOpenPosition{ value: securityDeposit }(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);
        // wait 1 minute to provide a fresh price
        skip(1 minutes);

        // set the wstETH price to liquidate the rebalancer position
        {
            wstEthPrice = 1200 ether;
            uint128 ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice)) / 1e10;
            mockPyth.setPrice(int64(uint64(ethPrice)));
            mockPyth.setLastPublishTime(block.timestamp);
            wstEthPrice = uint128(wstETH.getStETHByWstETH(ethPrice * 1e10));
        }

        // liquidate the rebalancer's tick
        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);
        // sanity check
        assertEq(
            prevPosId.tickVersion + 1, protocol.getTickVersion(prevPosId.tick), "Rebalancer tick was not liquidated"
        );

        // another user deposits in the rebalancer to re-trigger it later
        wstETH.mintAndApprove(USER_1, amountInRebalancer, address(rebalancer), type(uint256).max);
        vm.startPrank(USER_1);
        rebalancer.initiateDepositAssets(amountInRebalancer, USER_1);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        vm.stopPrank();

        // revert with a protocol error as the tick should not be accessible anymore
        // but the _lastLiquidatedVersion has not been updated yet
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, 1, 0));
        rebalancer.initiateClosePosition{ value: securityDeposit }(
            1 ether, address(this), DISABLE_MIN_PRICE, MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA
        );

        // wait 1 minute to provide a fresh price
        skip(1 minutes);

        // set the wstETH price to liquidate the rebalancer position
        {
            wstEthPrice = 1000 ether;
            uint128 ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice)) / 1e10;
            mockPyth.setPrice(int64(uint64(ethPrice)));
            mockPyth.setLastPublishTime(block.timestamp);
            wstEthPrice = uint128(wstETH.getStETHByWstETH(ethPrice * 1e10));
        }

        // liquidate the position we created earlier and trigger the rebalancer
        vm.expectEmit(false, false, false, false);
        emit PositionVersionUpdated(0, 0, 0, PositionId(0, 0, 0));
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);
        // sanity checks
        assertEq(newPosId.tickVersion + 1, protocol.getTickVersion(newPosId.tick), "Position tick was not liquidated");
        assertEq(rebalancer.getLastLiquidatedVersion(), version, "Liquidated version should have been updated");

        // compensate imbalance to allow rebalancer users to close
        protocol.initiateOpenPosition{ value: securityDeposit }(
            20 ether,
            800 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            payable(address(this)),
            payable(address(this)),
            NO_PERMIT2,
            "",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateOpenPosition{ value: securityDeposit }(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        // wait 1 minute to provide a fresh price
        skip(1 minutes);

        // try to withdraw from the rebalancer again
        vm.expectRevert(IRebalancerErrors.RebalancerUserLiquidated.selector);
        rebalancer.initiateClosePosition{ value: securityDeposit + 1 ether }(
            amountInRebalancer, address(this), DISABLE_MIN_PRICE, MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA
        );
    }

    receive() external payable { }
}
