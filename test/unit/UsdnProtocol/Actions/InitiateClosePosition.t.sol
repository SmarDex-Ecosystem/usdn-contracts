// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { ADMIN, DEPLOYER, USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The initiate close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 * @custom:and a validated long position of 1 ether with 10x leverage
 */
contract TestUsdnProtocolActionsInitiateClosePosition is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 private constant POSITION_AMOUNT = 1 ether;
    PositionId private posId;
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user tries to close a position with an amount higher than the position's amount
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with an amount too high
     * @custom:then The call reverts
     */
    function test_RevertWhen_closePartialPositionWithAmountHigherThanPositionAmount() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        uint128 amountToClose = POSITION_AMOUNT + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolAmountToCloseHigherThanPositionAmount.selector, amountToClose, POSITION_AMOUNT
            )
        );
        protocol.i_initiateClosePosition(
            Types.InitiateClosePositionParams({
                to: address(this),
                validator: payable(address(this)),
                deadline: type(uint256).max,
                posId: posId,
                amountToClose: amountToClose,
                userMinPrice: DISABLE_MIN_PRICE,
                securityDepositValue: 0,
                domainSeparatorV4: ""
            }),
            priceData,
            ""
        );
    }

    /**
     * @custom:scenario A user tries to close a position with a remaining amount lower than the min long position
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with
     * an amount higher than POSITION_AMOUNT - minLongPosition
     * @custom:then The call reverts with the UsdnProtocolLongPositionTooSmall error
     */
    function test_RevertWhen_closePartialPositionWithAmountRemainingLowerThanMinLongPosition() public {
        vm.prank(ADMIN);
        protocol.setMinLongPosition(POSITION_AMOUNT / 2);

        bytes memory priceData = abi.encode(params.initialPrice);
        uint128 amountToClose = POSITION_AMOUNT / 2 + 1;

        // Sanity check
        assertLt(
            POSITION_AMOUNT - amountToClose,
            POSITION_AMOUNT / 2,
            "The amount remaining is too high to trigger the error"
        );

        vm.expectRevert(UsdnProtocolLongPositionTooSmall.selector);
        protocol.i_initiateClosePosition(
            Types.InitiateClosePositionParams({
                to: address(this),
                validator: payable(address(this)),
                deadline: type(uint256).max,
                posId: posId,
                amountToClose: amountToClose,
                userMinPrice: DISABLE_MIN_PRICE,
                securityDepositValue: 0,
                domainSeparatorV4: ""
            }),
            priceData,
            ""
        );
    }

    /**
     * @custom:scenario The sender is not the owner of the position
     * @custom:when The user initiates a close of another user's position
     * @custom:then The protocol reverts with `UsdnProtocolUnauthorized`
     */
    function test_RevertWhen_notUser() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        vm.expectRevert(UsdnProtocolUnauthorized.selector);
        vm.prank(USER_1);
        protocol.i_initiateClosePosition(
            Types.InitiateClosePositionParams({
                to: address(this),
                validator: USER_1,
                deadline: type(uint256).max,
                posId: posId,
                amountToClose: POSITION_AMOUNT,
                userMinPrice: DISABLE_MIN_PRICE,
                securityDepositValue: 0,
                domainSeparatorV4: ""
            }),
            priceData,
            ""
        );
    }

    /**
     * @custom:scenario The user initiates a close position with parameter to defined at zero
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates a close position with parameter to defined at zero
     * @custom:then The protocol reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_zeroAddressTo() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.i_initiateClosePosition(
            Types.InitiateClosePositionParams({
                to: address(0),
                validator: payable(address(this)),
                deadline: type(uint256).max,
                posId: posId,
                amountToClose: POSITION_AMOUNT,
                userMinPrice: DISABLE_MIN_PRICE,
                securityDepositValue: 0,
                domainSeparatorV4: ""
            }),
            priceData,
            ""
        );
    }

    /**
     * @custom:scenario A user tries to close a position with 0 as the amount to close
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with 0 as the amount to close
     * @custom:then The call reverts
     */
    function test_RevertWhen_closePartialPositionWithZeroAmount() public {
        bytes memory priceData = abi.encode(params.initialPrice);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolZeroAmount.selector));
        protocol.i_initiateClosePosition(
            Types.InitiateClosePositionParams({
                to: address(this),
                validator: payable(address(this)),
                deadline: type(uint256).max,
                posId: posId,
                amountToClose: 0,
                userMinPrice: DISABLE_MIN_PRICE,
                securityDepositValue: 0,
                domainSeparatorV4: ""
            }),
            priceData,
            ""
        );
    }

    /**
     * @custom:scenario A user tries to close a position that was previously liquidated
     * @custom:given A validated open position gets liquidated
     * @custom:when The owner of the position calls initiateClosePosition with half of the amount
     * @custom:then The call reverts because the position is not valid anymore
     */
    function test_RevertWhen_closePartialPositionWithAnOutdatedTick() public {
        _waitBeforeLiquidation();
        bytes memory priceData = abi.encode(protocol.getEffectivePriceForTick(posId.tick));

        // we need wait delay to make the new price data fresh
        _waitDelay();
        // Liquidate the position
        protocol.mockLiquidate(priceData);
        (, uint256 version) = protocol.i_tickHash(posId.tick);
        assertGt(version, posId.tickVersion, "The tick should have been liquidated");

        // Try to close the position once the price comes back up
        priceData = abi.encode(params.initialPrice);
        vm.expectRevert(
            abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, posId.tickVersion + 1, posId.tickVersion)
        );
        protocol.i_initiateClosePosition(
            Types.InitiateClosePositionParams({
                to: address(this),
                validator: payable(address(this)),
                deadline: type(uint256).max,
                posId: posId,
                amountToClose: POSITION_AMOUNT / 2,
                userMinPrice: DISABLE_MIN_PRICE,
                securityDepositValue: 0,
                domainSeparatorV4: ""
            }),
            priceData,
            ""
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                            initiateClosePosition                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user initiates a close position action but sends too much ether
     * @custom:given A validated long position
     * @custom:and oracle validation cost == 0
     * @custom:when User calls initiateClosePosition with an amount of ether greater than the validation cost
     * @custom:then The protocol refunds the amount sent
     */
    function test_initiateClosePositionRefundExcessEther() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        uint256 etherBalanceBefore = address(this).balance;

        protocol.initiateClosePosition{ value: 1 ether }(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );

        assertEq(
            etherBalanceBefore,
            address(this).balance,
            "The sent ether should have been refunded as none of it was spent"
        );
    }

    /**
     * @custom:scenario A user initiates a close position action with a pending action
     * @custom:given A validated long position
     * @custom:and an initiated open position action from another user
     * @custom:when User calls initiateClosePosition with valid price data for the pending action
     * @custom:then The user validates the pending action
     */
    function test_initiateClosePositionValidatePendingAction() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        // Initiate an open position action for another user
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        skip(protocol.getLowLatencyValidatorDeadline());

        bytes[] memory previousData = new bytes[](1);
        previousData[0] = priceData;
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 1;

        vm.expectEmit(true, true, false, false);
        emit ValidatedOpenPosition(USER_1, USER_1, 0, 0, PositionId(0, 0, 0));
        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            PreviousActionsData(previousData, rawIndices),
            ""
        );
    }

    /**
     * @custom:scenario A user initiates a close position action
     * @custom:given A validated long position
     * @custom:when User calls initiateClosePosition
     * @custom:then The user initiates a close position action for his position
     */
    function test_initiateClosePosition() public {
        bytes memory priceData = abi.encode(params.initialPrice);

        vm.expectEmit();
        emit InitiatedClosePosition(
            address(this), address(this), address(this), posId, POSITION_AMOUNT, POSITION_AMOUNT, 0
        );
        bool success = protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );
        assertTrue(success, "success");
    }

    /**
     * @custom:scenario Closing a position that was not validated yet
     * @custom:given A position that is pending validation and has a validator different from the owner
     * @custom:when The owner tries to close the position
     * @custom:then The transaction reverts with UsdnProtocolPositionNotValidated
     */
    function test_RevertWhen_initiateClosePendingPosition() public {
        bytes memory priceData = abi.encode(params.initialPrice);

        wstETH.mintAndApprove(address(this), POSITION_AMOUNT, address(protocol), type(uint256).max);
        (, posId) = protocol.initiateOpenPosition(
            POSITION_AMOUNT,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            USER_1,
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        vm.expectRevert(UsdnProtocolPositionNotValidated.selector);
        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                           _initiateClosePosition                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Initiate close a position fully
     * @custom:given A validated open position
     * @custom:when The owner of the position closes all of the position at the same price as the opening
     * @custom:then The state of the protocol is updated
     * @custom:and an InitiatedClosePosition event is emitted
     * @custom:and the position is deleted
     */
    function test_internalInitiateClosePosition() public {
        _internalInitiateClosePositionScenario(address(this), address(this));
    }

    /**
     * @custom:scenario Initiate close a position fully
     * @custom:given A validated open position
     * @custom:when The owner of the position closes all of the position at the same price as the opening
     * @custom:and the to parameter is different from the sender
     * @custom:then The state of the protocol is updated
     * @custom:and an InitiatedClosePosition event is emitted
     * @custom:and the position is deleted
     */
    function test_internalInitiateClosePositionForAnotherUser() public {
        _internalInitiateClosePositionScenario(USER_1, address(this));
    }

    /**
     * @custom:scenario Initiate close a position fully
     * @custom:given A validated open position
     * @custom:when The owner of the position closes all of the position at the same price as the opening
     * @custom:and the validator parameter is different from the sender
     * @custom:then The state of the protocol is updated
     * @custom:and an {InitiatedClosePosition} event is emitted
     * @custom:and the position is deleted
     */
    function test_internalInitiateClosePositionDifferentValidator() public {
        _internalInitiateClosePositionScenario(address(this), USER_1);
    }

    /**
     * @custom:scenario Initiate close a position fully
     * @custom:given A validated open position
     * @custom:when The owner of the position closes all of the position at the same price as the opening
     * @custom:and the `to` parameter is different from the sender
     * @custom:and the `validator` parameter is different from the sender
     * @custom:and the `validator` parameter is different from the `to` parameter
     * @custom:then The state of the protocol is updated
     * @custom:and an {InitiatedClosePosition} event is emitted
     * @custom:and the position is deleted
     */
    function test_internalInitiateClosePositionForAnotherUserDifferentValidator() public {
        _internalInitiateClosePositionScenario(USER_1, USER_2);
    }

    function _internalInitiateClosePositionScenario(address to, address validator) internal {
        uint256 totalLongPositionBefore = protocol.getTotalLongPositions();
        TickData memory tickData = protocol.getTickData(posId.tick);
        _initiateCloseAPositionHelper(POSITION_AMOUNT, to, validator);

        /* ---------------------------- Position's state ---------------------------- */
        (Position memory posAfter,) = protocol.getLongPosition(posId);
        assertEq(posAfter.user, address(0), "The user of the position should have been reset");
        assertEq(posAfter.timestamp, 0, "Timestamp of the position should have been reset");
        assertEq(posAfter.totalExpo, 0, "The total expo of the position should be 0");
        assertEq(posAfter.amount, 0, "The amount of the position should be 0");

        /* ---------------------------- Protocol's State ---------------------------- */
        TickData memory newTickData = protocol.getTickData(posId.tick);
        assertEq(
            totalLongPositionBefore - 1,
            protocol.getTotalLongPositions(),
            "The amount of long positions should have decreased by one"
        );
        assertEq(
            tickData.totalPos - 1,
            newTickData.totalPos,
            "The amount of long positions on the tick should have decreased by one"
        );
    }

    /**
     * @custom:scenario Initiate close a position partially
     * @custom:given A validated open position
     * @custom:when The owner of the position closes half of the position at the same price as the opening
     * @custom:then The state of the protocol is updated
     * @custom:and an InitiatedClosePosition event is emitted
     * @custom:and the position still exists
     */
    function test_internalInitiateClosePositionPartially() public {
        uint128 amountToClose = POSITION_AMOUNT / 2;
        uint256 totalLongPositionBefore = protocol.getTotalLongPositions();
        TickData memory tickData = protocol.getTickData(posId.tick);
        (Position memory posBefore,) = protocol.getLongPosition(posId);
        uint128 totalExpoToClose =
            FixedPointMathLib.fullMulDiv(posBefore.totalExpo, amountToClose, posBefore.amount).toUint128();
        _initiateCloseAPositionHelper(amountToClose, address(this), address(this));

        /* ---------------------------- Position's state ---------------------------- */
        (Position memory posAfter,) = protocol.getLongPosition(posId);
        assertEq(posBefore.user, posAfter.user, "The user of the position should not have changed");
        assertEq(posBefore.timestamp, posAfter.timestamp, "Timestamp of the position should have stayed the same");
        assertEq(
            posBefore.totalExpo - totalExpoToClose,
            posAfter.totalExpo,
            "The total expo to close should have been subtracted from the original total expo of the position"
        );
        assertEq(
            posBefore.amount - amountToClose,
            posAfter.amount,
            "The amount to close should have been subtracted from the original amount of the position"
        );

        /* ---------------------------- Protocol's State ---------------------------- */
        TickData memory newTickData = protocol.getTickData(posId.tick);
        assertEq(
            totalLongPositionBefore,
            protocol.getTotalLongPositions(),
            "The amount of long positions should not have changed"
        );
        assertEq(
            tickData.totalPos, newTickData.totalPos, "The amount of long positions on the tick should not have changed"
        );
    }

    /**
     * @custom:scenario A initiate close liquidates a pending tick but is not initiated because of being liquidated
     * @custom:given An existing user position
     * @custom:when The `initiateClosePosition` function is called with a price below the position's liq price
     * @custom:then The position's tick is liquidated
     * @custom:and The close action isn't initiated
     */
    function test_initiateClosePositionLiquidated() public {
        _waitMockMiddlewarePriceDelay();

        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            abi.encode(params.initialPrice * 2 / 3),
            EMPTY_PREVIOUS_DATA,
            ""
        );

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        assertEq(uint256(pending.action), uint256(ProtocolAction.None), "action should not be initiated");

        assertEq(
            posId.tickVersion + 1, protocol.getTickVersion(posId.tick), "user position should have been liquidated"
        );
    }

    /**
     * @custom:scenario A initiate close liquidates a pending tick but is not initiated because a tick still needs to
     * be liquidated
     * @custom:given The user position with a liq price above the deployer position's liq price
     * @custom:when The deployer calls `initiateClosePosition` with a price below both positions' liq price
     * @custom:then The user position's tick is liquidated
     * @custom:and The deployer's close action isn't initiated due to its own position needing to be liquidated
     */
    function test_initiateClosePositionIsPendingLiquidation() public {
        _waitMockMiddlewarePriceDelay();

        vm.prank(DEPLOYER);
        bool success = protocol.initiateClosePosition(
            initialPosition,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            DEPLOYER,
            DEPLOYER,
            type(uint256).max,
            abi.encode(params.initialPrice / 3),
            EMPTY_PREVIOUS_DATA,
            ""
        );
        assertFalse(success, "success");

        PendingAction memory pending = protocol.getUserPendingAction(DEPLOYER);
        assertEq(uint256(pending.action), uint256(ProtocolAction.None), "pending action should not exist");

        assertEq(
            posId.tickVersion + 1, protocol.getTickVersion(posId.tick), "setup position should have been liquidated"
        );
    }

    /**
     * @notice Helper function to avoid duplicating code between the partial and full close position tests
     * @param amountToClose Amount of the position to close
     */
    function _initiateCloseAPositionHelper(uint128 amountToClose, address to, address validator) internal {
        (Position memory posBefore,) = protocol.getLongPosition(posId);
        uint128 totalExpoToClose =
            FixedPointMathLib.fullMulDiv(posBefore.totalExpo, amountToClose, posBefore.amount).toUint128();
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 balanceLongBefore = protocol.getBalanceLong();
        uint256 assetToTransfer = protocol.i_assetToRemove(
            balanceLongBefore,
            params.initialPrice,
            protocol.getEffectivePriceForTick(
                protocol.i_calcTickWithoutPenalty(posId.tick),
                params.initialPrice,
                totalExpoBefore - balanceLongBefore,
                protocol.getLiqMultiplierAccumulator()
            ),
            totalExpoToClose
        );

        TickData memory tickData = protocol.getTickData(posId.tick);

        /* ------------------------ Initiate the close action ----------------------- */
        vm.expectEmit();
        emit InitiatedClosePosition(
            address(this), // owner
            validator, // validator
            to,
            posId,
            posBefore.amount,
            amountToClose,
            posBefore.totalExpo - totalExpoToClose
        );
        protocol.i_initiateClosePosition(
            Types.InitiateClosePositionParams({
                to: to,
                validator: payable(validator),
                deadline: type(uint256).max,
                posId: posId,
                amountToClose: amountToClose,
                userMinPrice: DISABLE_MIN_PRICE,
                securityDepositValue: 0,
                domainSeparatorV4: ""
            }),
            abi.encode(params.initialPrice),
            ""
        );

        /* ------------------------- Pending action's state ------------------------- */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(validator));
        assertTrue(action.action == ProtocolAction.ValidateClosePosition, "The action type is wrong");
        assertEq(action.timestamp, block.timestamp, "The block timestamp should be now");
        assertEq(action.to, to, "To is wrong");
        assertEq(action.validator, validator, "Validator is wrong");
        assertEq(action.tick, posId.tick, "The position tick is wrong");
        assertEq(
            action.closePosTotalExpo,
            totalExpoToClose,
            "Total expo of pending action should be equal to totalExpoToClose"
        );
        assertEq(
            action.closeAmount, amountToClose, "Amount of the pending action should be equal to the amount to close"
        );
        assertEq(action.tickVersion, posId.tickVersion, "The tick version should not have changed");
        assertEq(action.index, posId.index, "The index should not have changed");
        assertEq(action.closeBoundedPositionValue, assetToTransfer, "The pos value should not have changed");

        /* ----------------------------- Protocol State ----------------------------- */
        TickData memory newTickData = protocol.getTickData(posId.tick);
        assertEq(
            totalExpoBefore - totalExpoToClose,
            protocol.getTotalExpo(),
            "totalExpoToClose should have been subtracted from the total expo of the protocol"
        );
        assertEq(
            tickData.totalExpo - totalExpoToClose,
            newTickData.totalExpo,
            "totalExpoToClose should have been subtracted to the total expo on the tick"
        );
        assertEq(
            balanceLongBefore - assetToTransfer,
            protocol.getBalanceLong(),
            "assetToTransfer should have been subtracted from the long balance of the protocol"
        );
    }

    /**
     * @custom:scenario When the last position in a tick is getting closed, the tick data should be reset
     * @custom:given A position that was opened with a penalty of 500 ticks
     * @custom:when The user closes the position
     * @custom:then The liquidation penalty in the tick data should be reset to 0
     */
    function test_initiateCloseResetTickPenalty() public {
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(500);

        PositionId memory newPosId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice / 4,
                price: params.initialPrice
            })
        );

        TickData memory tickData = protocol.getTickData(newPosId.tick);
        assertEq(tickData.liquidationPenalty, 0, "penalty should be reset");
        assertEq(tickData.totalPos, 0, "position was removed from the tick");
    }

    /**
     * @notice Helper function to set up a mock rebalancer position with two users
     * @param userDeposit Amount to deposit for a single user
     * @return rebalancerPos_ The position ID of the rebalancer position
     */
    function _setUpMockRebalancerPosition(uint88 userDeposit) internal returns (PositionId memory rebalancerPos_) {
        vm.startPrank(ADMIN);
        rebalancer.setMinAssetDeposit(userDeposit);
        protocol.setRebalancer(rebalancer);
        vm.stopPrank();

        wstETH.mintAndApprove(USER_1, userDeposit, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_2, userDeposit, address(rebalancer), type(uint256).max);
        vm.prank(USER_1);
        rebalancer.initiateDepositAssets(userDeposit, USER_1);
        vm.prank(USER_2);
        rebalancer.initiateDepositAssets(userDeposit, USER_2);
        skip(rebalancer.getTimeLimits().validationDelay);
        vm.prank(USER_1);
        rebalancer.validateDepositAssets();
        vm.prank(USER_2);
        rebalancer.validateDepositAssets();

        vm.startPrank(address(rebalancer));
        wstETH.approve(address(protocol), type(uint256).max);
        (, rebalancerPos_) = protocol.initiateOpenPosition(
            2 * userDeposit,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(rebalancer),
            payable(address(rebalancer)),
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateOpenPosition(
            payable(address(rebalancer)), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();
    }

    /**
     * @custom:scenario A rebalancer user closes their position completely
     * @custom:given The user has deposited 1 ether in the rebalancer
     * @custom:and The rebalancer's position has 4 ether of initial collateral
     * @custom:and The minimum long position in the protocol is changed to 2 ether
     * @custom:when The user closes their position completely (1 ether) through a rebalancer partial close
     * @custom:then The partial close is authorized and successful
     */
    function test_closePartialFromRebalancerPositionTooSmall() public {
        uint88 minAssetDeposit = 1 ether;

        PositionId memory rebalancerPos = _setUpMockRebalancerPosition(minAssetDeposit);

        vm.prank(ADMIN);
        protocol.setMinLongPosition(2 * minAssetDeposit);

        vm.prank(address(rebalancer));
        protocol.initiateClosePosition(
            rebalancerPos,
            minAssetDeposit,
            DISABLE_MIN_PRICE,
            USER_1,
            USER_1,
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /**
     * @custom:scenario A rebalancer user closes their position partially when the position is too small
     * @custom:given The user has deposited 1 ether in the rebalancer
     * @custom:and The rebalancer's position has 4 ether of initial collateral
     * @custom:and The minimum long position in the protocol is changed to 2 ether
     * @custom:when The user closes their position partially (0.1 ether) through a rebalancer partial close
     * @custom:then The partial close is unauthorized and reverts with `UsdnProtocolLongPositionTooSmall`
     */
    function test_RevertWhen_closePartialFromRebalancerPartialUserClose() public {
        uint88 minAssetDeposit = 1 ether;

        PositionId memory rebalancerPos = _setUpMockRebalancerPosition(minAssetDeposit);

        vm.prank(ADMIN);
        protocol.setMinLongPosition(2 * minAssetDeposit);

        vm.expectRevert(UsdnProtocolLongPositionTooSmall.selector);
        vm.prank(address(rebalancer));
        protocol.initiateClosePosition(
            rebalancerPos,
            minAssetDeposit / 2,
            DISABLE_MIN_PRICE,
            USER_1,
            USER_1,
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /**
     * @custom:scenario The user initiates a close position action with an exit price less than the user's min price
     * @custom:given The current price is $2000
     * @custom:when The user initiates a close position with a userMinPrice of $2001
     * @custom:then The protocol reverts with UsdnProtocolSlippageMinPriceExceeded
     */
    function test_RevertWhen_initiateClosePositionWithExitPriceLessThanUserMinPrice() public {
        vm.expectRevert(UsdnProtocolSlippageMinPriceExceeded.selector);
        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            params.initialPrice + 1,
            address(this),
            payable(address(this)),
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /**
     * @custom:scenario The user initiates a close position action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls initiateClosePosition with too much ether
     * @custom:and A receive() function that calls initiateClosePosition again
     * @custom:when The user calls initiateClosePosition again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_initiateClosePositionCalledWithReentrancy() public {
        // If we are currently in a reentrancy
        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.initiateClosePosition(
                posId,
                POSITION_AMOUNT,
                DISABLE_MIN_PRICE,
                address(this),
                payable(address(this)),
                type(uint256).max,
                abi.encode(params.initialPrice),
                EMPTY_PREVIOUS_DATA,
                ""
            );
            return;
        }

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.initiateClosePosition.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateClosePosition{ value: 1 }(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /**
     * @custom:scenario The user sign a transaction to close a position with a deadline in the future. Transaction stays
     * in the mempool and the deadline is exceeded
     * @custom:given A user position
     * @custom:when The protocol receives a transaction to initiates a close position action with a deadline in the past
     * @custom:then The protocol reverts with UsdnProtocolDeadlineExceeded
     */
    function test_RevertWhen_initiateClosePositionDeadlineExceeded() public {
        vm.expectRevert(UsdnProtocolDeadlineExceeded.selector);
        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(this),
            block.timestamp - 1,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /**
     * @custom:scenario A user initiates a delegated close position with the position owner signature
     * @custom:given A validated long position
     * @custom:and A valid position owner signature
     * @custom:when User calls initiateClosePosition with the signature
     * @custom:then The user initiates a delegated close position
     */
    function test_initiateClosePositionDelegation() public {
        uint256 pk = 1;
        address user = vm.addr(pk);

        uint256 initialNonce = protocol.getNonce(user);

        posId = setUpUserPositionInLong(
            OpenParams({
                user: user,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        InitiateClosePositionDelegation memory delegation = InitiateClosePositionDelegation({
            posIdHash: keccak256(abi.encode(posId)),
            amountToClose: POSITION_AMOUNT,
            userMinPrice: DISABLE_MIN_PRICE,
            to: user,
            deadline: type(uint256).max,
            positionOwner: user,
            positionCloser: address(this),
            nonce: initialNonce
        });

        bool success = protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            user,
            payable(address(this)),
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA,
            _getDelegationSignature(pk, protocol.domainSeparatorV4(), delegation)
        );

        assertTrue(success, "success");
        assertEq(protocol.getNonce(user), initialNonce + 1, "User nonce should be incremented");
    }

    /// @dev Allow refund tests
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_initiateClosePositionCalledWithReentrancy();
            _reenter = false;
        }
    }
}
