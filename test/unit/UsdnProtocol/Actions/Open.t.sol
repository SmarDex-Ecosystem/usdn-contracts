// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN, USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction,
    TickData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The open position function of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolOpenPosition is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint256 internal constant LONG_AMOUNT = 1 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;

    struct ValueToCheckBefore {
        uint256 balance;
        uint256 protocolBalance;
        uint256 totalPositions;
        uint256 totalExpo;
        uint256 balanceLong;
    }

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableProtocolFees = false;
        params.flags.enableFunding = false;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
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
        uint128 expectedLeverage = uint128(
            (10 ** protocol.LEVERAGE_DECIMALS() * CURRENT_PRICE)
                / (
                    CURRENT_PRICE
                        - protocol.getEffectivePriceForTick(
                            expectedTick - int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing()
                        )
                )
        );

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
            expectedLeverage,
            uint128(LONG_AMOUNT),
            CURRENT_PRICE,
            expectedTick,
            0,
            0
        ); // expected event
        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, to
        );
        uint256 tickLiqPrice = protocol.getEffectivePriceForTick(
            tick - int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing()
        );

        // check state after opening the position
        assertEq(tick, expectedTick, "tick number");
        assertEq(tickVersion, 0, "tick version");
        assertEq(index, 0, "index");

        assertEq(wstETH.balanceOf(address(this)), before.balance - LONG_AMOUNT, "user wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), before.protocolBalance + LONG_AMOUNT, "protocol wstETH balance");
        assertEq(protocol.getTotalLongPositions(), before.totalPositions + 1, "total long positions");
        uint256 positionExpo =
            protocol.i_calculatePositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, uint128(tickLiqPrice));
        assertEq(protocol.getTotalExpo(), before.totalExpo + positionExpo, "protocol total expo");
        TickData memory tickData = protocol.getTickData(expectedTick);
        assertEq(tickData.totalExpo, positionExpo, "total expo in tick");
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
        (position,) = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(position.user, to, "user position");
        assertEq(position.timestamp, action.timestamp, "timestamp position");
        assertEq(position.amount, uint128(LONG_AMOUNT), "amount position");
        assertEq(position.totalExpo, positionExpo, "totalExpo position");

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
        (int24 tick,,) = setUpUserPositionInLong(
            OpenParams(
                USER_1, ProtocolAction.ValidateOpenPosition, uint128(LONG_AMOUNT), desiredLiqPrice, CURRENT_PRICE
            )
        );

        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(originalLiqPenalty); // restore liquidation penalty
        assertEq(
            protocol.getTickLiquidationPenalty(tick), storedLiqPenalty, "liquidation penalty of the tick was stored"
        );

        uint128 expectedLiqPrice =
            protocol.getEffectivePriceForTick(tick - int24(uint24(storedLiqPenalty)) * protocol.getTickSpacing());
        uint256 expectedTotalExpo =
            protocol.i_calculatePositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, expectedLiqPrice);

        // create position which ends up in the same tick
        (int24 tick2, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );
        assertEq(tick2, tick, "tick is the same");
        (Position memory pos, uint8 liqPenalty) = protocol.getLongPosition(tick2, tickVersion, index);
        assertEq(pos.totalExpo, expectedTotalExpo, "pos total expo indicates that the stored penalty was used");
        assertEq(liqPenalty, storedLiqPenalty, "pos liquidation penalty");
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
     * @custom:when The user initiates an open position with the address to at 0
     * @custom:then The protocol reverts with UsdnProtocolZeroAddressTo
     */
    function test_RevertWhen_zeroAddressTo() public {
        vm.expectRevert(UsdnProtocolZeroAddressTo.selector);
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

        int24 expectedTick = protocol.getEffectiveTickForPrice(CURRENT_PRICE, protocol.getLiquidationMultiplier());
        uint128 expectedLiqPrice = protocol.getEffectivePriceForTick(expectedTick, protocol.getLiquidationMultiplier());

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
     * @custom:scenario The user validates an open position action
     * @custom:given The user has initiated an open position with 1 wstETH and a desired liquidation price of ~1333$
     * @custom:and the price was 2000$ at the moment of initiation
     * @custom:and the price has increased to 2100$
     * @custom:when The user validates the open position with the new price
     * @custom:then The protocol validates the position and emits the ValidatedOpenPosition event
     * @custom:and the position's leverage decreases
     * @custom:and the rest of the state changes as expected
     */
    function test_validateOpenPosition() public {
        _validateOpenPositionScenario(address(this));
    }

    /**
     * @custom:scenario The user validates an open position action for another user
     * @custom:given The user has initiated an open position with 1 wstETH and a desired liquidation price of ~1333$
     * @custom:and the price was 2000$ at the moment of initiation
     * @custom:and the price has increased to 2100$
     * @custom:when The user validates the open position with the new price
     * @custom:then The owner of the position is the previously defined user
     */
    function test_validateOpenPositionForAnotherUser() public {
        _validateOpenPositionScenario(USER_1);
    }

    function _validateOpenPositionScenario(address to) internal {
        uint256 initialTotalExpo = protocol.getTotalExpo();
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, to
        );
        (Position memory tempPos,) = protocol.getLongPosition(tick, tickVersion, index);

        _waitDelay();

        uint128 newPrice = CURRENT_PRICE + 100 ether;

        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(address(this), to, 0, newPrice, tick, tickVersion, index);
        protocol.validateOpenPosition(abi.encode(newPrice), EMPTY_PREVIOUS_DATA);

        (Position memory pos,) = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(pos.user, tempPos.user, "user");
        assertEq(pos.timestamp, tempPos.timestamp, "timestamp");
        // price increased -> total expo decreased
        assertLt(pos.totalExpo, tempPos.totalExpo, "totalExpo");

        TickData memory tickData = protocol.getTickData(tick);
        assertEq(tickData.totalExpo, pos.totalExpo, "total expo in tick");
        assertEq(protocol.getTotalExpo(), initialTotalExpo + pos.totalExpo, "total expo");
    }

    /**
     * @custom:scenario The user validates an open position action with a price that would increase the leverage above
     * the maximum allowed leverage
     * @custom:given The user has initiated an open position with 1 wstETH and a desired liquidation price of ~1800$
     * @custom:and the price was 2000$ at the moment of initiation
     * @custom:and the price has decreased to 1900$
     * @custom:when The user validates the open position with the new price
     * @custom:then The protocol validates the position and emits the ValidatedOpenPosition event
     * @custom:and the position is moved to another lower tick (to avoid exceeding the max leverage)
     * @custom:and the position's leverage stays below the max leverage
     */
    function test_validateOpenPositionAboveMaxLeverage() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 9 / 10; // leverage approx 10x
        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );
        (Position memory tempPos,) = protocol.getLongPosition(tick, tickVersion, index);

        _waitDelay();

        uint128 newPrice = CURRENT_PRICE - 100 ether;
        uint128 newLiqPrice = protocol.i_getLiquidationPrice(newPrice, uint128(protocol.getMaxLeverage()));
        int24 newTick = protocol.getEffectiveTickForPrice(newLiqPrice)
            + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        uint256 newTickVersion = protocol.getTickVersion(newTick);
        TickData memory tickData = protocol.getTickData(newTick);
        uint256 newIndex = tickData.totalPos;

        vm.expectEmit();
        emit LiquidationPriceUpdated(tick, tickVersion, index, newTick, newTickVersion, newIndex);
        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(address(this), address(this), 0, newPrice, newTick, newTickVersion, newIndex);
        protocol.validateOpenPosition(abi.encode(newPrice), EMPTY_PREVIOUS_DATA);

        (Position memory pos,) = protocol.getLongPosition(newTick, newTickVersion, newIndex);
        assertEq(pos.user, tempPos.user, "user");
        assertEq(pos.timestamp, tempPos.timestamp, "timestamp");
        assertEq(pos.amount, tempPos.amount, "amount");
        assertLt(newTick, tick, "tick");
        assertGt(pos.totalExpo, tempPos.totalExpo, "totalExpo");
    }

    /**
     * @custom:scenario The user validates an open position action with a price that increases the leverage above the
     * max leverage, but the target tick's penalty makes it remain above the max leverage
     * @custom:given The user will validate a position with a price that would increase the leverage above the max
     * leverage, in a tick which has a liquidation penalty lower than the current setting
     * @custom:when The user validates the open position with the new price
     * @custom:then The protocol validates the position in a new tick, but the leverage remains above the max leverage
     */
    function test_validateOpenPositionAboveMaxLeverageDifferentPenalty() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 9 / 10; // leverage approx 10x
        uint8 originalLiqPenalty = protocol.getLiquidationPenalty();
        uint8 storedLiqPenalty = originalLiqPenalty - 1;

        // calculate the future expected tick for the position we will validate later
        uint128 validatePrice = CURRENT_PRICE - 100 ether;
        uint128 tempLiqPrice = protocol.i_getLiquidationPrice(validatePrice, uint128(protocol.getMaxLeverage()));
        int24 validateTick = protocol.getEffectiveTickForPrice(tempLiqPrice)
            + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();

        // open another user position to set the tick's penalty to a lower value in storage
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(storedLiqPenalty);
        (int24 otherTick,,) = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                uint128(LONG_AMOUNT),
                protocol.getEffectivePriceForTick(validateTick),
                CURRENT_PRICE
            )
        );
        assertEq(otherTick, validateTick, "both positions in same tick");

        // restore liquidation penalty to original value
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(originalLiqPenalty);

        // initiate deposit with leverage close to 10x
        (int24 tempTick, uint256 tempTickVersion, uint256 tempIndex) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );

        _waitDelay();

        // expected values
        uint256 validateTickVersion = protocol.getTickVersion(validateTick);
        TickData memory tickData = protocol.getTickData(validateTick);
        uint256 validateIndex = tickData.totalPos;
        uint128 expectedLiqPrice = protocol.getEffectivePriceForTick(
            validateTick - int24(uint24(storedLiqPenalty)) * protocol.getTickSpacing()
        );
        uint128 expectedLeverage = protocol.i_getLeverage(validatePrice, expectedLiqPrice);
        // final leverage should be above 10x because of the stored liquidation penalty of the target tick
        assertGt(expectedLeverage, uint128(10 * 10 ** protocol.LEVERAGE_DECIMALS()), "final leverage");

        // validate deposit with a lower entry price
        vm.expectEmit();
        emit LiquidationPriceUpdated(
            tempTick, tempTickVersion, tempIndex, validateTick, validateTickVersion, validateIndex
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(
            address(this),
            address(this),
            expectedLeverage,
            validatePrice,
            validateTick,
            validateTickVersion,
            validateIndex
        );
        protocol.validateOpenPosition(abi.encode(validatePrice), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario A pending new long position gets liquidated
     * @custom:given A pending new position was liquidated before being validated
     * @custom:and The pending action is stale (tick version mismatch)
     * @custom:when The user opens another position
     * @custom:then The protocol emits a `StalePendingActionRemoved` event
     * @custom:and The transaction does not revert
     */
    function test_stalePendingActionReInit() public {
        (int24 tick, uint256 tickVersion, uint256 index) = _createStalePendingActionHelper();

        wstETH.approve(address(protocol), 1 ether);
        bytes memory priceData = abi.encode(uint128(1500 ether));
        // we should be able to open a new position
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, EMPTY_PREVIOUS_DATA, address(this));
    }

    /**
     * @custom:scenario A pending new long position gets liquidated and then validated
     * @custom:given A pending new position was liquidated before being validated
     * @custom:and The pending action is stale (tick version mismatch)
     * @custom:when The user tries to validate the pending action
     * @custom:then The protocol emits a `StalePendingActionRemoved` event
     * @custom:and The transaction does not revert
     */
    function test_stalePendingActionValidate() public {
        (int24 tick, uint256 tickVersion, uint256 index) = _createStalePendingActionHelper();

        bytes memory priceData = abi.encode(uint128(1500 ether));
        // validating the action emits the proper event
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.validateOpenPosition(priceData, EMPTY_PREVIOUS_DATA);
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
     * @custom:scenario The user sends too much ether when validate a position opening
     * @custom:given The user has initiated an open position
     * @custom:when The user sends 0.5 ether as value in the `validateOpenPosition` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_validateOpenPositionEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation

        bytes memory priceData = abi.encode(CURRENT_PRICE);
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        protocol.initiateOpenPosition{
            value: oracleMiddleware.validationCost(priceData, ProtocolAction.InitiateOpenPosition)
        }(uint128(LONG_AMOUNT), desiredLiqPrice, priceData, EMPTY_PREVIOUS_DATA, address(this));
        _waitDelay();
        uint256 balanceBefore = address(this).balance;
        uint256 validationCost = oracleMiddleware.validationCost(priceData, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: 0.5 ether }(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    // test refunds
    receive() external payable { }
}
