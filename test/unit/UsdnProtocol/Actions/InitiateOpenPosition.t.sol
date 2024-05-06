// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN, USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction,
    TickData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The initiateOpenPosition function of the UsdnProtocolActions contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsInitiateOpenPosition is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint256 internal constant LONG_AMOUNT = 1 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;
    uint256 internal securityDeposit;

    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    struct ValueToCheckBefore {
        uint256 balance;
        uint256 protocolBalance;
        uint256 totalPositions;
        uint256 totalExpo;
        uint256 balanceLong;
    }

    struct TestData {
        uint128 validatePrice;
        int24 validateTick;
        uint8 originalLiqPenalty;
        PositionId tempPosId;
        uint256 validateTickVersion;
        uint256 validateIndex;
        uint128 expectedLeverage;
    }

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
        securityDeposit = securityDeposit;
    }

    /**
     * @custom:scenario The user initiates an open position action
     * @custom:given The amount of collateral is 1 wstETH and the current price is 2000$
     * @custom:when The user initiates an open position with 1 wstETH and a desired liquidation price of ~1333$ (approx
     * 3x leverage)
     * @custom:then The protocol creates the position and emits the InitiatedOpenPosition event
     * @custom:and the state changes are as expected
     */
    function test_initiateOpenPosition() public {
        _initiateOpenPositionScenario(address(this));
    }

    /**
     * @custom:scenario The user initiates an open position action for another user
     * @custom:given The amount of collateral is 1 wstETH and the current price is 2000$
     * @custom:when The sender initiates an open position with 1 wstETH and a desired liquidation price of ~1333$
     * (approx 3x leverage)
     * @custom:then The protocol creates the position for the defined
     * user and emits the InitiatedOpenPosition event
     * @custom:and the state changes are as expected
     */
    function test_initiateOpenPositionForAnotherAddress() public {
        _initiateOpenPositionScenario(USER_1);
    }

    function _initiateOpenPositionScenario(address to) internal {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);
        uint128 liqPriceWithoutPenalty =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(expectedTick));
        uint128 expectedPosTotalExpo =
            protocol.i_calculatePositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, liqPriceWithoutPenalty);

        // state before opening the position
        ValueToCheckBefore memory before = ValueToCheckBefore({
            balance: wstETH.balanceOf(address(this)),
            protocolBalance: wstETH.balanceOf(address(protocol)),
            totalPositions: protocol.getTotalLongPositions(),
            totalExpo: protocol.getTotalExpo(),
            balanceLong: uint256(protocol.i_longAssetAvailable(CURRENT_PRICE))
        });

        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this),
            to,
            uint40(block.timestamp),
            expectedPosTotalExpo,
            uint128(LONG_AMOUNT),
            CURRENT_PRICE,
            PositionId(expectedTick, 0, 0)
        );
        PositionId memory posId = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, to
        );

        // check state after opening the position
        assertEq(posId.tick, expectedTick, "tick number");
        assertEq(posId.tickVersion, 0, "tick version");
        assertEq(posId.index, 0, "index");

        assertEq(wstETH.balanceOf(address(this)), before.balance - LONG_AMOUNT, "user wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), before.protocolBalance + LONG_AMOUNT, "protocol wstETH balance");
        assertEq(protocol.getTotalLongPositions(), before.totalPositions + 1, "total long positions");
        assertEq(protocol.getTotalExpo(), before.totalExpo + expectedPosTotalExpo, "protocol total expo");
        TickData memory tickData = protocol.getTickData(expectedTick);
        assertEq(tickData.totalExpo, expectedPosTotalExpo, "total expo in tick");
        assertEq(tickData.totalPos, 1, "positions in tick");
        assertEq(protocol.getBalanceLong(), before.balanceLong + LONG_AMOUNT, "balance of long side");

        // the pending action should not yet be actionable by a third party
        (PendingAction[] memory pendingActions,) = protocol.getActionablePendingActions(address(0));
        assertEq(pendingActions.length, 0, "no pending action");

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.action == ProtocolAction.ValidateOpenPosition, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.to, to, "action to");
        assertEq(action.tick, expectedTick, "action tick");
        assertEq(action.tickVersion, 0, "action tickVersion");
        assertEq(action.index, 0, "action index");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (pendingActions,) = protocol.getActionablePendingActions(address(0));
        action = protocol.i_toLongPendingAction(pendingActions[0]);
        assertEq(action.user, address(this), "pending action user");

        Position memory position;
        (position,) = protocol.getLongPosition(posId);
        assertEq(position.user, to, "user position");
        assertEq(position.timestamp, action.timestamp, "timestamp position");
        assertEq(position.amount, uint128(LONG_AMOUNT), "amount position");
        assertEq(position.totalExpo, expectedPosTotalExpo, "totalExpo position");

        vm.stopPrank();
    }

    /**
     * @custom:scenario A user opens a position in a tick that had a different liquidation penalty than the current
     * value.
     * @custom:given A tick with an existing position and a different liquidation penalty than the current value
     * @custom:when The user opens a new position in the same tick
     * @custom:then The new position is opened with the stored liquidation penalty and not the current one
     */
    function test_initiateOpenPositionDifferentPenalty() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 9 / 10; // leverage approx 10x
        uint8 originalLiqPenalty = protocol.getLiquidationPenalty();
        uint8 storedLiqPenalty = originalLiqPenalty - 1;

        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(storedLiqPenalty); // set a different liquidation penalty
        // this position is opened to set the liquidation penalty of the tick
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: uint128(LONG_AMOUNT),
                desiredLiqPrice: desiredLiqPrice,
                price: CURRENT_PRICE
            })
        );

        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(originalLiqPenalty); // restore liquidation penalty
        assertEq(
            protocol.getTickLiquidationPenalty(posId.tick),
            storedLiqPenalty,
            "liquidation penalty of the tick was stored"
        );

        uint128 expectedLiqPrice =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick, storedLiqPenalty));
        uint256 expectedTotalExpo =
            protocol.i_calculatePositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, expectedLiqPrice);

        // create position which ends up in the same tick
        PositionId memory posId2 = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );
        assertEq(posId.tick, posId2.tick, "tick is the same");
        (Position memory pos, uint8 liqPenalty) = protocol.getLongPosition(posId);
        assertEq(pos.totalExpo, expectedTotalExpo, "pos total expo indicates that the stored penalty was used");
        assertEq(liqPenalty, storedLiqPenalty, "pos liquidation penalty");
    }

    /**
     * @custom:scenario A initiate open position liquidates a pending tick but is not validated
     * because a tick still need to be liquidated
     * @custom:given The initial open position
     * @custom:and A first user open position
     * @custom:and The price drop below all position liquidation prices
     * @custom:when The first `initiateOpenPosition` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The first user open position tick still need to be liquidated
     * @custom:and The second user open position isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateOpenPosition` is called
     * @custom:and The first user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The second user open position is validated
     * @custom:then The transaction is completed
     */
    function test_initiateOpenPositionIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                uint128(LONG_AMOUNT),
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateOpenPosition(
                uint128(LONG_AMOUNT),
                params.initialPrice / 30,
                abi.encode(params.initialPrice / 10),
                EMPTY_PREVIOUS_DATA,
                address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "action is initiated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");

            assertEq(wstethBalanceBefore, wstETH.balanceOf(address(this)), "wsteth balance changed");
        }

        _waitMockMiddlewarePriceDelay();

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateOpenPosition(
                uint128(LONG_AMOUNT),
                params.initialPrice / 30,
                abi.encode(params.initialPrice / 10),
                EMPTY_PREVIOUS_DATA,
                address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateOpenPosition), "action is not initiated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );

            assertGt(wstethBalanceBefore, wstETH.balanceOf(address(this)), "wsteth balance not changed");
        }
    }

    /**
     * @custom:scenario A initiate open position liquidates a tick but is not validated
     * because a tick still need to be liquidated. In the same block another open
     * liquid the remaining tick and is validated
     * @custom:given The initial open position
     * @custom:and A first user open position
     * @custom:and The price drop below all position liquidation prices
     * @custom:when The first `initiateOpenPosition` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The first user open position tick still need to be liquidated
     * @custom:and The second user open position isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateOpenPosition` is called in the same block
     * @custom:and The first user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The second user open position is validated
     * @custom:then The transaction is completed
     */
    function test_initiateOpenPositionSameBlockIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                uint128(LONG_AMOUNT),
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateOpenPosition(
                uint128(LONG_AMOUNT),
                params.initialPrice / 30,
                abi.encode(params.initialPrice / 10),
                EMPTY_PREVIOUS_DATA,
                address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "action is initiated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");

            assertEq(wstethBalanceBefore, wstETH.balanceOf(address(this)), "wsteth balance changed");
        }

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateOpenPosition(
                uint128(LONG_AMOUNT),
                params.initialPrice / 30,
                abi.encode(params.initialPrice / 10),
                EMPTY_PREVIOUS_DATA,
                address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateOpenPosition), "action is not initiated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );

            assertGt(wstethBalanceBefore, wstETH.balanceOf(address(this)), "wsteth balance not changed");
        }
    }

    /**
     * @custom:scenario A validate open position liquidates a pending tick but is not validated
     * because a tick still need to be liquidated
     * @custom:given The initial open position
     * @custom:and A first user open position
     * @custom:and A second initiated user open position with a liquidation price below all others
     * @custom:and The price drop below the initiate and the first user open position
     * @custom:when The first `validateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The first user open position tick still need to be liquidated
     * @custom:and The user initiated open position isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `validateDeposit` is called
     * @custom:and The first user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user initiated open position is validated
     * @custom:then The transaction is completed
     */
    function test_validateOpenIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user open position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                uint128(LONG_AMOUNT),
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            protocol.initiateOpenPosition{ value: securityDeposit }(
                uint128(LONG_AMOUNT),
                params.initialPrice / 30,
                abi.encode(params.initialPrice),
                EMPTY_PREVIOUS_DATA,
                address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(
                uint256(pending.action), uint256(ProtocolAction.ValidateOpenPosition), "user action is not initiated"
            );

            _waitDelay();

            protocol.validateOpenPosition{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateOpenPosition), "user action was validated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");
        }

        _waitMockMiddlewarePriceDelay();

        {
            protocol.validateOpenPosition{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user action was not validated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );
        }
    }

    /**
     * @custom:scenario A validate open position liquidates a pending tick but is not validated
     * because a tick still need to be liquidated. In the same block another validate
     * liquid the remaining tick and is validated
     * @custom:given The initial open position
     * @custom:and A first user open position
     * @custom:and A second initiated user open position with a liquidation price below all others
     * @custom:and The price drop below the initiate and the first user open position
     * @custom:when The first `validateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The first user open position tick still need to be liquidated
     * @custom:and The user initiated open position isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `validateDeposit` is called
     * @custom:and The first user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user initiated open position is validated
     * @custom:then The transaction is completed
     */
    function test_validateOpenSameBlockIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user open position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                uint128(LONG_AMOUNT),
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            protocol.initiateOpenPosition{ value: securityDeposit }(
                uint128(LONG_AMOUNT),
                params.initialPrice / 30,
                abi.encode(params.initialPrice),
                EMPTY_PREVIOUS_DATA,
                address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(
                uint256(pending.action), uint256(ProtocolAction.ValidateOpenPosition), "user action is not initiated"
            );

            _waitDelay();

            protocol.validateOpenPosition{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateOpenPosition), "user action was validated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");
        }

        {
            protocol.validateOpenPosition{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user action was not validated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );
        }
    }

    /**
     * @custom:scenario The user initiates an open position action with a zero amount
     * @custom:when The user initiates an open position with 0 wstETH
     * @custom:then The protocol reverts with UsdnProtocolZeroAmount
     */
    function test_RevertWhen_initiateOpenPositionZeroAmount() public {
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateOpenPosition(0, 2000 ether, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this));
    }

    /**
     * @custom:scenario The user initiates an open position action with no recipient
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates an open position with the address to at 0
     * @custom:then The protocol reverts with UsdnProtocolInvalidAddressTo
     */
    function test_RevertWhen_zeroAddressTo() public {
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.initiateOpenPosition(1 ether, 2000 ether, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(0));
    }

    /**
     * @custom:scenario The user initiates an open position action with a leverage that's too low
     * @custom:when The user initiates an open position with a desired liquidation price of $0.0000000000001
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooLow
     */
    function test_RevertWhen_initiateOpenPositionLowLeverage() public {
        vm.expectRevert(UsdnProtocolLeverageTooLow.selector);
        protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), 100_000, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with a leverage that's too high
     * @custom:given The maximum leverage is 10x and the current price is $2000
     * @custom:when The user initiates an open position with a desired liquidation price of $1854
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooHigh
     */
    function test_RevertWhen_initiateOpenPositionHighLeverage() public {
        // max liquidation price without liquidation penalty
        uint256 maxLiquidationPrice = protocol.i_getLiquidationPrice(CURRENT_PRICE, uint128(protocol.getMaxLeverage()));
        // add 3% to be above max liquidation price including penalty
        uint128 desiredLiqPrice = uint128(maxLiquidationPrice * 1.03 ether / 1 ether);

        vm.expectRevert(UsdnProtocolLeverageTooHigh.selector);
        protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with not enough safety margin
     * @custom:given The safety margin is 2% and the current price is $2000
     * @custom:and The maximum leverage is 100x
     * @custom:when The user initiates an open position with a desired liquidation price of $2000
     * @custom:then The protocol reverts with UsdnProtocolLiquidationPriceSafetyMargin
     */
    function test_RevertWhen_initiateOpenPositionSafetyMargin() public {
        // set the max leverage very high to allow for such a case
        uint8 leverageDecimals = protocol.LEVERAGE_DECIMALS();
        vm.prank(ADMIN);
        protocol.setMaxLeverage(uint128(100 * 10 ** leverageDecimals));

        // calculate expected error values
        uint128 expectedMaxLiqPrice =
            uint128(CURRENT_PRICE * (protocol.BPS_DIVISOR() - protocol.getSafetyMarginBps()) / protocol.BPS_DIVISOR());

        int24 expectedTick = protocol.getEffectiveTickForPrice(CURRENT_PRICE);
        uint128 expectedLiqPrice = protocol.getEffectivePriceForTick(expectedTick);

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolLiquidationPriceSafetyMargin.selector, expectedLiqPrice, expectedMaxLiqPrice
            )
        );
        protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), CURRENT_PRICE, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    /**
     * @custom:scenario A pending new long position gets liquidated
     * @custom:given A pending new position was liquidated before being validated
     * @custom:and The pending action is stale (tick version mismatch)
     * @custom:when The user opens another position
     * @custom:then The protocol emits a `StalePendingActionRemoved` event
     * @custom:and The transaction does not revert
     */
    function test_initiateOpenPositionWithStalePendingAction() public {
        PositionId memory posId = _createStalePendingActionHelper();

        wstETH.approve(address(protocol), 1 ether);
        bytes memory priceData = abi.encode(uint128(1500 ether));
        // we should be able to open a new position
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, EMPTY_PREVIOUS_DATA, address(this));
    }

    /**
     * @custom:scenario The user sends too much ether when initiating a position opening
     * @custom:given The user opens a position
     * @custom:when The user sends 0.5 ether as value in the `initiateOpenPosition` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_initiateOpenPositionEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        uint256 balanceBefore = address(this).balance;
        bytes memory priceData = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(priceData, ProtocolAction.InitiateOpenPosition);
        protocol.initiateOpenPosition{ value: 0.5 ether }(
            uint128(LONG_AMOUNT), 1000 ether, priceData, EMPTY_PREVIOUS_DATA, address(this)
        );
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The user initiates an open position action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls initiateOpenPosition with too much ether
     * @custom:and A receive() function that calls initiateOpenPosition again
     * @custom:when The user calls initiateOpenPosition again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_initiateOpenPositionCalledWithReentrancy() public {
        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.initiateOpenPosition(
                1 ether, 1500 ether, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
            );
            return;
        }

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.initiateOpenPosition.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateOpenPosition{ value: 1 }(
            1 ether, 1500 ether, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_initiateOpenPositionCalledWithReentrancy();
            _reenter = false;
        }
    }
}
