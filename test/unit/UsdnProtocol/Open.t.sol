// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction,
    PreviousActionsData
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

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mint(address(this), INITIAL_WSTETH_BALANCE);
        wstETH.approve(address(protocol), type(uint256).max);
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
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);
        uint128 expectedLeverage = uint128(
            (10 ** protocol.LEVERAGE_DECIMALS() * CURRENT_PRICE)
                / (
                    CURRENT_PRICE
                        - protocol.getEffectivePriceForTick(
                            expectedTick - int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing()
                        )
                )
        );

        // state before opening the position
        uint256 balanceBefore = wstETH.balanceOf(address(this));
        uint256 protocolBalanceBefore = wstETH.balanceOf(address(protocol));
        uint256 totalPositionsBefore = protocol.getTotalLongPositions();
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 balanceLongBefore = uint256(protocol.i_longAssetAvailable(CURRENT_PRICE));

        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this),
            uint40(block.timestamp),
            expectedLeverage,
            uint128(LONG_AMOUNT),
            CURRENT_PRICE,
            expectedTick,
            0,
            0
        ); // expected event
        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            uint96(LONG_AMOUNT),
            desiredLiqPrice,
            abi.encode(CURRENT_PRICE),
            PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        uint256 tickLiqPrice = protocol.getEffectivePriceForTick(
            tick - int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing()
        );

        // check state after opening the position
        assertEq(tick, expectedTick, "tick number");
        assertEq(tickVersion, 0, "tick version");
        assertEq(index, 0, "index");

        assertEq(wstETH.balanceOf(address(this)), balanceBefore - LONG_AMOUNT, "user wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), protocolBalanceBefore + LONG_AMOUNT, "protocol wstETH balance");
        assertEq(protocol.getTotalLongPositions(), totalPositionsBefore + 1, "total long positions");
        uint256 positionExpo =
            protocol.i_calculatePositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, uint128(tickLiqPrice));
        assertEq(protocol.getTotalExpo(), totalExpoBefore + positionExpo, "protocol total expo");
        assertEq(protocol.getTotalExpoByTick(expectedTick, tickVersion), positionExpo, "total expo in tick");
        assertEq(protocol.getPositionsInTick(expectedTick, tickVersion), 1, "positions in tick");
        assertEq(protocol.getBalanceLong(), balanceLongBefore + LONG_AMOUNT, "balance of long side");

        // the pending action should not yet be actionable by a third party
        vm.startPrank(address(0)); // simulate front-end calls by someone else
        (PendingAction[] memory pendingActions,) = protocol.getActionablePendingActions();
        assertEq(pendingActions.length, 0, "no pending action");

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.action == ProtocolAction.ValidateOpenPosition, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.tick, expectedTick, "action tick");
        assertEq(action.tickVersion, 0, "action tickVersion");
        assertEq(action.index, 0, "action index");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (pendingActions,) = protocol.getActionablePendingActions();
        action = protocol.i_toLongPendingAction(pendingActions[0]);
        assertEq(action.user, address(this), "pending action user");
        vm.stopPrank();
    }

    /**
     * @custom:scenario The user initiates an open position action with a zero amount
     * @custom:when The user initiates an open position with 0 wstETH
     * @custom:then The protocol reverts with UsdnProtocolZeroAmount
     */
    function test_RevertWhen_initiateOpenPositionZeroAmount() public {
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateOpenPosition(
            0, 2000 ether, abi.encode(CURRENT_PRICE), PreviousActionsData(new bytes[](0), new uint128[](0))
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with a leverage that's too low
     * @custom:when The user initiates an open position with a desired liquidation price of $0.0000000000001
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooLow
     */
    function test_RevertWhen_initiateOpenPositionLowLeverage() public {
        vm.expectRevert(UsdnProtocolLeverageTooLow.selector);
        protocol.initiateOpenPosition(
            uint96(LONG_AMOUNT),
            100_000,
            abi.encode(CURRENT_PRICE),
            PreviousActionsData(new bytes[](0), new uint128[](0))
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
            uint96(LONG_AMOUNT),
            desiredLiqPrice,
            abi.encode(CURRENT_PRICE),
            PreviousActionsData(new bytes[](0), new uint128[](0))
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
            uint96(LONG_AMOUNT),
            CURRENT_PRICE,
            abi.encode(CURRENT_PRICE),
            PreviousActionsData(new bytes[](0), new uint128[](0))
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
        uint256 initialTotalExpo = protocol.getTotalExpo();
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            uint96(LONG_AMOUNT),
            desiredLiqPrice,
            abi.encode(CURRENT_PRICE),
            PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        Position memory tempPos = protocol.getLongPosition(tick, tickVersion, index);

        _waitDelay();

        uint128 newPrice = CURRENT_PRICE + 100 ether;

        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(address(this), 0, newPrice, tick, tickVersion, index);
        protocol.validateOpenPosition(abi.encode(newPrice), PreviousActionsData(new bytes[](0), new uint128[](0)));

        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(pos.user, tempPos.user, "user");
        assertEq(pos.timestamp, tempPos.timestamp, "timestamp");
        // price increased -> total expo decreased
        assertLt(pos.totalExpo, tempPos.totalExpo, "totalExpo");

        assertEq(protocol.getTotalExpoByTick(tick, tickVersion), pos.totalExpo, "total expo in tick");
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
            uint96(LONG_AMOUNT),
            desiredLiqPrice,
            abi.encode(CURRENT_PRICE),
            PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        Position memory tempPos = protocol.getLongPosition(tick, tickVersion, index);

        _waitDelay();

        uint128 newPrice = CURRENT_PRICE - 100 ether;
        uint128 newLiqPrice = protocol.i_getLiquidationPrice(newPrice, uint128(protocol.getMaxLeverage()));
        int24 newTick = protocol.getEffectiveTickForPrice(newLiqPrice)
            + int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing();
        uint256 newTickVersion = protocol.getTickVersion(newTick);
        uint256 newIndex = protocol.getPositionsInTick(newTick, newTickVersion);

        vm.expectEmit();
        emit LiquidationPriceUpdated(tick, tickVersion, index, newTick, newTickVersion, newIndex);
        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(address(this), 0, newPrice, newTick, newTickVersion, newIndex);
        protocol.validateOpenPosition(abi.encode(newPrice), PreviousActionsData(new bytes[](0), new uint128[](0)));

        Position memory pos = protocol.getLongPosition(newTick, newTickVersion, newIndex);
        assertEq(pos.user, tempPos.user, "user");
        assertEq(pos.timestamp, tempPos.timestamp, "timestamp");
        assertEq(pos.amount, tempPos.amount, "amount");
        assertLt(newTick, tick, "tick");
        assertGt(pos.totalExpo, tempPos.totalExpo, "totalExpo");
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

        bytes memory priceData = abi.encode(uint128(1500 ether));
        // we should be able to open a new position
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.initiateOpenPosition(
            1 ether, 1000 ether, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
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
        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));
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
            uint96(LONG_AMOUNT), 1000 ether, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
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
        }(uint96(LONG_AMOUNT), desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));
        _waitDelay();
        uint256 balanceBefore = address(this).balance;
        uint256 validationCost = oracleMiddleware.validationCost(priceData, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: 0.5 ether }(
            priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @dev Helper function to initiate a new position and liquidate it before it gets validated
     * @return tick_ The tick of the new position
     * @return tickVersion_ The tick version of the new position
     * @return index_ The index of the new position
     */
    function _createStalePendingActionHelper() internal returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        wstETH.mintAndApprove(address(this), 2 ether, address(protocol), type(uint256).max);
        // create a pending action with a liquidation price around $1700
        bytes memory priceData = abi.encode(uint128(2000 ether));
        (tick_, tickVersion_, index_) = protocol.initiateOpenPosition(
            1 ether, 1700 ether, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        // the price drops to $1500 and the position gets liquidated
        skip(30);
        priceData = abi.encode(uint128(1500 ether));
        protocol.liquidate(priceData, 10);

        // the pending action is stale
        uint256 currentTickVersion = protocol.getTickVersion(tick_);
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.var3, tickVersion_, "tick version");
        assertTrue(action.var3 != currentTickVersion, "current tick version");
    }

    // test refunds
    receive() external payable { }
}
