// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { DEPLOYER, SET_EXTERNAL_MANAGER, SET_PROTOCOL_PARAMS_MANAGER, USER_1 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IBaseRebalancer } from "../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancer } from "../../../src/interfaces/Rebalancer/IRebalancer.sol";
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
    uint128 internal securityDeposit;
    uint256 internal constant USER_PK = 1;
    address user = vm.addr(USER_PK);

    struct InitiateClosePositionDelegation {
        uint88 amount;
        address to;
        uint256 userMinPrice;
        uint256 deadline;
        address depositOwner;
        address depositCloser;
        uint256 nonce;
    }

    function setUp() public {
        (, amountInRebalancer,,) = _setUpImbalanced(payable(user), 15 ether);
        uint256 maxLeverage = protocol.getMaxLeverage();
        vm.prank(DEPLOYER);
        rebalancer.setPositionMaxLeverage(maxLeverage);
        skip(5 minutes);

        wstEthPrice = _setOraclePrices(1490 ether);

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA);

        version = rebalancer.getPositionVersion();
        previousPositionData = rebalancer.getPositionData(version);
        prevPosId = PositionId({
            tick: previousPositionData.tick,
            tickVersion: previousPositionData.tickVersion,
            index: previousPositionData.index
        });
        (protocolPosition,) = protocol.getLongPosition(prevPosId);
        securityDeposit = protocol.getSecurityDepositValue();
        skip(rebalancer.getTimeLimits().closeDelay + 1);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
    }

    function test_setUp() public view {
        assertGt(rebalancer.getPositionVersion(), 0, "The rebalancer version should be updated");
        assertGt(protocolPosition.amount - previousPositionData.amount, 0, "The protocol bonus should be positive");
    }

    /**
     * @custom:scenario Verify that a user can't withdraw from the rebalancer just after it was triggered
     * @custom:given A rebalancer that just opened a position
     * @custom:when The user calls the rebalancer's `initiateClosePosition`
     * @custom:then The call reverts because of the imbalance
     */
    function test_rebalancerNoWithdrawalAfterRebalancerTrigger() public {
        vm.expectPartialRevert(UsdnProtocolImbalanceLimitReached.selector);
        vm.prank(user);
        rebalancer.initiateClosePosition{ value: securityDeposit }(
            amountInRebalancer,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA,
            ""
        );
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
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        mockChainlinkOnChain.setLastPrice(int256(wstETH.getWstETHByStETH(uint256(1370 ether / 10 ** (18 - 8)))));

        // choose an amount small enough to not trigger imbalance limits
        uint88 amount = amountInRebalancer / 200;

        uint256 amountToCloseWithoutBonus = FixedPointMathLib.fullMulDiv(
            amount,
            previousPositionData.entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(user).entryPositionVersion).entryAccMultiplier
        );

        uint256 amountToClose = amountToCloseWithoutBonus
            + amountToCloseWithoutBonus * (protocolPosition.amount - previousPositionData.amount)
                / previousPositionData.amount;

        vm.expectEmit();
        emit ClosePositionInitiated(user, amount, amountToClose, amountInRebalancer - amount);
        vm.prank(user);
        (bool success) = rebalancer.initiateClosePosition{ value: securityDeposit }(
            amount, address(this), payable(this), DISABLE_MIN_PRICE, type(uint256).max, "", EMPTY_PREVIOUS_DATA, ""
        );

        assertTrue(success, "The rebalancer close should be successful");

        amountInRebalancer -= amount;

        UserDeposit memory depositData = rebalancer.getUserDepositData(user);

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
        vm.prank(user);
        vm.expectPartialRevert(UsdnProtocolImbalanceLimitReached.selector);
        rebalancer.initiateClosePosition{ value: securityDeposit }(
            amount, address(this), payable(this), DISABLE_MIN_PRICE, type(uint256).max, "", EMPTY_PREVIOUS_DATA, ""
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
            rebalancer.getPositionData(rebalancer.getUserDepositData(user).entryPositionVersion).entryAccMultiplier
        );

        uint256 amountToClose = amountToCloseWithoutBonus
            + amountToCloseWithoutBonus * (protocolPosition.amount - previousPositionData.amount)
                / previousPositionData.amount;

        vm.prank(user);
        vm.expectEmit();
        emit ClosePositionInitiated(user, amountInRebalancer, amountToClose, 0);
        (bool success) = rebalancer.initiateClosePosition{ value: securityDeposit }(
            amountInRebalancer,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA,
            ""
        );

        UserDeposit memory depositData = rebalancer.getUserDepositData(user);

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
     * @custom:scenario A user closing its position through the rebalancer can also liquidate ticks
     * @custom:given A tick can be liquidated in the USDN protocol
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function
     * @custom:then A ClosePositionInitiated event is emitted
     * @custom:and The user depositData is deleted
     * @custom:and The position data is updated
     * @custom:and The user initiate close position is pending in protocol
     * @custom:and The user receives the liquidation rewards
     */
    function test_rebalancerInitiateClosePositionLiquidatesAPosition() public {
        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        skip(1 hours);
        // put the eth price a bit higher to avoid liquidating existing position
        wstEthPrice = _setOraclePrices(wstEthPrice * 15 / 10);

        vm.startPrank(user);
        // open a position to liquidate during the initiateClose call
        (, PositionId memory posId) = protocol.initiateOpenPosition{ value: securityDeposit }(
            2 ether,
            wstEthPrice * 9 / 10,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        vm.stopPrank();

        skip(1 hours);
        // put the price below the above position's liquidation price
        wstEthPrice = _setOraclePrices(wstEthPrice * 8 / 10);

        uint256 amountToCloseWithoutBonus = FixedPointMathLib.fullMulDiv(
            amountInRebalancer,
            rebalancer.getPositionData(rebalancer.getPositionVersion()).entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(user).entryPositionVersion).entryAccMultiplier
        );

        uint256 amountToClose = amountToCloseWithoutBonus
            + amountToCloseWithoutBonus * (protocolPosition.amount - previousPositionData.amount)
                / previousPositionData.amount;

        uint256 balanceOfRebalancerBefore = wstETH.balanceOf(address(rebalancer));
        LiqTickInfo[] memory liqTickInfoArray;

        // snapshot and liquidate to get the liquidated ticks data
        uint256 snapshotId = vm.snapshot();
        liqTickInfoArray = protocol.liquidate{
            value: oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation)
        }(MOCK_PYTH_DATA);
        vm.revertTo(snapshotId);

        uint256 liquidationRewards = liquidationRewardsManager.getLiquidationRewards(
            liqTickInfoArray, wstEthPrice, false, RebalancerAction.None, ProtocolAction.InitiateClosePosition, "", ""
        );

        vm.expectEmit(false, true, false, false);
        emit LiquidatedTick(posId.tick, 0, 0, 0, 0);
        vm.expectEmit();
        emit ClosePositionInitiated(user, amountInRebalancer, amountToClose, 0);
        vm.expectEmit();
        emit Transfer(address(rebalancer), user, liquidationRewards);
        vm.prank(user);
        (bool success) = rebalancer.initiateClosePosition{ value: securityDeposit }(
            amountInRebalancer,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA,
            ""
        );

        UserDeposit memory depositData = rebalancer.getUserDepositData(user);

        assertTrue(success, "The rebalancer close should be successful");
        assertEq(depositData.amount, 0, "The user's deposited amount in rebalancer should be zero");
        assertEq(depositData.entryPositionVersion, 0, "The user's entry position version should be zero");

        assertEq(
            balanceOfRebalancerBefore,
            wstETH.balanceOf(address(rebalancer)),
            "The wstETH balance of the rebalancer should not have changed"
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

        uint256 userBalanceBefore = user.balance;
        uint256 excessAmount = 1 ether;

        vm.prank(user);
        // send more ether than necessary to trigger the refund
        rebalancer.initiateClosePosition{ value: securityDeposit + excessAmount }(
            amountInRebalancer,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA,
            ""
        );

        assertEq(payable(rebalancer).balance, 0, "There should be no ether left in the rebalancer");
        assertEq(userBalanceBefore - securityDeposit, user.balance, "The overpaid amount should have been refunded");
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
        vm.startPrank(user);
        // compensate imbalance to allow rebalancer users to close
        (, PositionId memory newPosId) = protocol.initiateOpenPosition{ value: securityDeposit }(
            10 ether,
            1100 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateOpenPosition{ value: securityDeposit }(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();
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

        // liquidate the rebalancer's tick after disabling the rebalancer temporarily, so that it does not get
        // re-triggered
        // TODO: refactor this test so it's more robust
        vm.startPrank(SET_EXTERNAL_MANAGER);
        protocol.setRebalancer(IBaseRebalancer(address(0)));
        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA);
        // sanity check
        assertEq(
            prevPosId.tickVersion + 1, protocol.getTickVersion(prevPosId.tick), "Rebalancer tick was not liquidated"
        );
        protocol.setRebalancer(IBaseRebalancer(address(rebalancer)));
        vm.stopPrank();

        // another user deposits in the rebalancer to re-trigger it later
        wstETH.mintAndApprove(USER_1, amountInRebalancer, address(rebalancer), type(uint256).max);
        vm.startPrank(USER_1);
        rebalancer.initiateDepositAssets(amountInRebalancer, USER_1);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        vm.stopPrank();

        vm.warp(rebalancer.getCloseLockedUntil() + 1);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);

        vm.startPrank(user);
        // revert with a protocol error as the tick should not be accessible anymore
        // but the _lastLiquidatedVersion has not been updated yet
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, 1, 0));
        rebalancer.initiateClosePosition{ value: securityDeposit }(
            1 ether,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            MOCK_PYTH_DATA,
            EMPTY_PREVIOUS_DATA,
            ""
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
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA);
        // sanity checks
        assertEq(newPosId.tickVersion + 1, protocol.getTickVersion(newPosId.tick), "Position tick was not liquidated");
        assertEq(rebalancer.getLastLiquidatedVersion(), version, "Liquidated version should have been updated");

        // compensate imbalance to allow rebalancer users to close
        protocol.initiateOpenPosition{ value: securityDeposit }(
            20 ether,
            800 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateOpenPosition{ value: securityDeposit }(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        // wait 1 minute to provide a fresh price
        skip(1 minutes);

        vm.warp(rebalancer.getCloseLockedUntil() + 1);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);

        // try to withdraw from the rebalancer again
        vm.expectRevert(IRebalancerErrors.RebalancerUserLiquidated.selector);
        rebalancer.initiateClosePosition{ value: securityDeposit + 1 ether }(
            amountInRebalancer,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            MOCK_PYTH_DATA,
            EMPTY_PREVIOUS_DATA,
            ""
        );
        vm.stopPrank();
    }

    /**
     * @custom:scenario The imbalance is high enough so that the rebalancer is triggered during the liquidations inside
     * a rebalancer's initiateClosePosition call
     * @custom:given The rebalancer has been triggered once already and has an open position
     * @custom:and An imbalance high enough after a liquidation to trigger the rebalancer
     * @custom:when A user calls initiateClosePosition from the rebalancer
     * @custom:then The call reverts with a InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_rebalancerTriggerDuringInitClose() public {
        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 350, 0, 0);

        // deposit assets in the protocol to imbalance it
        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);
        vm.startPrank(user);
        protocol.initiateDeposit{ value: securityDeposit }(
            100 ether, DISABLE_SHARES_OUT_MIN, address(this), payable(this), type(uint256).max, "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        mockPyth.setLastPublishTime(block.timestamp - 1);

        protocol.validateDeposit{ value: oracleFee }(payable(address(this)), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        // open a position on the same tick as the rebalancer to avoid an underflow in case of regression
        (, PositionId memory tempPosId) = protocol.initiateOpenPosition{ value: securityDeposit }(
            protocolPosition.amount * 2, // put enough fund to avoid an underflow
            protocol.getEffectivePriceForTick(prevPosId.tick) + 10, // + 10 is enough to compensate the rounding down
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        assertEq(prevPosId.tick, tempPosId.tick, "The opened position should be on the same tick as the rebalancer");

        _waitDelay();
        oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: oracleFee }(payable(address(this)), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        // open a position to liquidate and trigger the rebalancer
        // put a high price to avoid liquidating other ticks later
        _setOraclePrices(2000 ether);
        (bool success,) = protocol.initiateOpenPosition{ value: securityDeposit }(
            2 ether,
            1750 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "Position should have been opened");

        _waitDelay();
        protocol.validateOpenPosition{ value: oracleFee }(payable(address(this)), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        skip(5 minutes);

        // set a price that liquidates the previously opened position
        _setOraclePrices(1700 ether);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        rebalancer.initiateClosePosition{ value: securityDeposit + oracleFee }(
            amountInRebalancer,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            MOCK_PYTH_DATA,
            EMPTY_PREVIOUS_DATA,
            ""
        );

        vm.stopPrank();
    }

    /**
     * @custom:scenario Closes entirely a rebalancer amount using delegation signature
     * @custom:when The user calls the rebalancer's `initiateClosePosition` function using delegation signature
     * @custom:then A ClosePositionInitiated event is emitted
     * @custom:and The user depositData is deleted
     * @custom:and The position data is updated
     * @custom:and The validator initiate close position is pending in protocol
     * @custom:and The user nonce should be incremented
     */
    function test_rebalancerInitiateClosePositionDelegation() public {
        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        uint256 amountToCloseWithoutBonus = FixedPointMathLib.fullMulDiv(
            amountInRebalancer,
            rebalancer.getPositionData(rebalancer.getPositionVersion()).entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(user).entryPositionVersion).entryAccMultiplier
        );

        uint256 amountToClose = amountToCloseWithoutBonus
            + amountToCloseWithoutBonus * (protocolPosition.amount - previousPositionData.amount)
                / previousPositionData.amount;

        uint256 initialNonce = rebalancer.getNonce(user);

        InitiateClosePositionDelegation memory delegation = InitiateClosePositionDelegation({
            amount: amountInRebalancer,
            to: user,
            userMinPrice: DISABLE_MIN_PRICE,
            deadline: type(uint256).max,
            depositOwner: user,
            depositCloser: address(this),
            nonce: initialNonce
        });

        bytes memory signature = _getDelegationSignature(USER_PK, delegation);
        bytes memory delegationData = abi.encode(user, signature);
        vm.expectEmit();
        emit ClosePositionInitiated(delegation.depositOwner, delegation.amount, amountToClose, 0);
        (bool success) = rebalancer.initiateClosePosition{ value: securityDeposit }(
            delegation.amount,
            delegation.to,
            payable(this),
            delegation.userMinPrice,
            delegation.deadline,
            "",
            EMPTY_PREVIOUS_DATA,
            delegationData
        );

        UserDeposit memory depositData = rebalancer.getUserDepositData(user);

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
            "The validator protocol action should pending"
        );

        assertEq(rebalancer.getNonce(user), initialNonce + 1, "The user nonce should be incremented");
    }

    /**
     * @custom:scenario A rebalancer user closes their position partially when
     * the protocol position is below the minimum
     * @custom:given The user has deposited in the rebalancer
     * @custom:and The rebalancer's position is initiated
     * @custom:and The rebalancer is set to the address zero
     * @custom:and The minimum long position in the protocol is changed to a large amount
     * @custom:and The rebalancer is set again
     * @custom:when The user closes their position partially with a remaining deposit above the minimum deposit
     * @custom:then The partial close reverts with {RebalancerInvalidAmount}
     */
    function test_RevertWhen_closePartialFromRebalancerBelowProtocolMin() public {
        vm.prank(SET_EXTERNAL_MANAGER);
        protocol.setRebalancer(IRebalancer(address(0)));

        vm.startPrank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setMinLongPosition(Constants.MAX_MIN_LONG_POSITION);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);
        vm.stopPrank();

        vm.prank(SET_EXTERNAL_MANAGER);
        protocol.setRebalancer(rebalancer);

        uint88 amountToRemove = uint88(amountInRebalancer - rebalancer.getMinAssetDeposit() + 1);

        vm.prank(user);
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAmount.selector);
        rebalancer.initiateClosePosition{ value: securityDeposit }(
            amountToRemove,
            address(this),
            payable(this),
            DISABLE_MIN_PRICE,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /**
     * @notice Get the delegation signature
     * @param privateKey The signer private key
     * @param delegationToSign The delegation struct to sign
     * @return delegationSignature_ The initiateClosePosition eip712 delegation signature
     */
    function _getDelegationSignature(uint256 privateKey, InitiateClosePositionDelegation memory delegationToSign)
        internal
        view
        returns (bytes memory delegationSignature_)
    {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            rebalancer.domainSeparatorV4(),
            keccak256(
                abi.encode(
                    rebalancer.INITIATE_CLOSE_TYPEHASH(),
                    delegationToSign.amount,
                    delegationToSign.to,
                    delegationToSign.userMinPrice,
                    delegationToSign.deadline,
                    delegationToSign.depositOwner,
                    delegationToSign.depositCloser,
                    delegationToSign.nonce
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        delegationSignature_ = abi.encodePacked(r, s, v);
    }

    receive() external payable { }
}
