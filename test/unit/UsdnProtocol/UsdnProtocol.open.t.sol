// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction, LongPendingAction, Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The open position function of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
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
                            expectedTick - int24(protocol.liquidationPenalty()) * protocol.tickSpacing()
                        )
                )
        );

        // state before opening the position
        uint256 balanceBefore = wstETH.balanceOf(address(this));
        uint256 protocolBalanceBefore = wstETH.balanceOf(address(protocol));
        uint256 totalPositionsBefore = protocol.totalLongPositions();
        uint256 totalExpoBefore = protocol.totalExpo();
        uint256 balanceLongBefore = uint256(protocol.longAssetAvailable(CURRENT_PRICE));

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
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(uint96(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), "");

        // check state after opening the position
        assertEq(tick, expectedTick, "tick number");
        assertEq(tickVersion, 0, "tick version");
        assertEq(index, 0, "index");

        assertEq(wstETH.balanceOf(address(this)), balanceBefore - LONG_AMOUNT, "user wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), protocolBalanceBefore + LONG_AMOUNT, "protocol wstETH balance");
        assertEq(protocol.totalLongPositions(), totalPositionsBefore + 1, "total long positions");
        assertEq(
            protocol.totalExpo(),
            totalExpoBefore + LONG_AMOUNT * expectedLeverage / uint256(10) ** protocol.LEVERAGE_DECIMALS(),
            "protocol total expo"
        );
        assertEq(
            protocol.totalExpoByTick(expectedTick),
            LONG_AMOUNT * expectedLeverage / uint256(10) ** protocol.LEVERAGE_DECIMALS(),
            "total expo in tick"
        );
        assertEq(protocol.positionsInTick(expectedTick), 1, "positions in tick");
        assertEq(protocol.balanceLong(), balanceLongBefore + LONG_AMOUNT, "balance of long side");

        // the pending action should not yet be actionable by a third party
        vm.startPrank(address(0)); // simulate front-end calls by someone else
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getActionablePendingAction(0));
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.action == ProtocolAction.ValidateOpenPosition, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.tick, expectedTick, "action tick");
        assertEq(action.tickVersion, 0, "action tickVersion");
        assertEq(action.index, 0, "action index");

        // the pending action should be actionable after the validation deadline
        skip(protocol.validationDeadline() + 1);
        action = protocol.i_toLongPendingAction(protocol.getActionablePendingAction(0));
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
        protocol.initiateOpenPosition(0, 2000 ether, abi.encode(CURRENT_PRICE), "");
    }

    /**
     * @custom:scenario The user initiates an open position action with a leverage that's too low
     * @custom:when The user initiates an open position with a desired liquidation price of $0.0000000000001
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooLow
     */
    function test_RevertWhen_initiateOpenPositionLowLeverage() public {
        vm.expectRevert(UsdnProtocolLeverageTooLow.selector);
        protocol.initiateOpenPosition(uint96(LONG_AMOUNT), 100_000, abi.encode(CURRENT_PRICE), "");
    }

    /**
     * @custom:scenario The user initiates an open position action with a leverage that's too high
     * @custom:given The maximum leverage is 10x and the current price is $2000
     * @custom:when The user initiates an open position with a desired liquidation price of $1854
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooHigh
     */
    function test_RevertWhen_initiateOpenPositionHighLeverage() public {
        // max liquidation price without liquidation penalty
        uint256 maxLiquidationPrice = protocol.getLiquidationPrice(CURRENT_PRICE, uint128(protocol.maxLeverage()));
        // add 3% to be above max liquidation price including penalty
        uint128 desiredLiqPrice = uint128(maxLiquidationPrice * 1.03 ether / 1 ether);

        vm.expectRevert(UsdnProtocolLeverageTooHigh.selector);
        protocol.initiateOpenPosition(uint96(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), "");
    }

    /**
     * @custom:scenario The user initiates an open position action with not enough safety margin
     * @custom:given The safety margin is 2% and the current price is $2000
     * @custom:and The maximum leverage is 1000x
     * @custom:when The user initiates an open position with a desired liquidation price of $2000
     * @custom:then The protocol reverts with UsdnProtocolLiquidationPriceSafetyMargin
     */
    function test_RevertWhen_initiateOpenPositionSafetyMargin() public {
        // set the max leverage very high to allow for such a case
        protocol.setMaxLeverage(uint128(1000 * 10 ** protocol.LEVERAGE_DECIMALS()));

        // calculate expected error values
        uint128 expectedMaxLiqPrice =
            uint128(CURRENT_PRICE * (protocol.BPS_DIVISOR() - protocol.getSafetyMarginBps()) / protocol.BPS_DIVISOR());
        // the oracle gives a timestamp 30 minutes in the past, we need the liq multiplier at that time to calculate
        // the tick price
        uint256 liqMultiplierAtPriceTimestamp =
            protocol.getLiquidationMultiplier(CURRENT_PRICE, uint128(block.timestamp - 30 minutes));
        int24 expectedTick = protocol.getEffectiveTickForPrice(CURRENT_PRICE, liqMultiplierAtPriceTimestamp);
        uint128 expectedLiqPrice = protocol.getEffectivePriceForTick(expectedTick, liqMultiplierAtPriceTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolLiquidationPriceSafetyMargin.selector, expectedLiqPrice, expectedMaxLiqPrice
            )
        );
        protocol.initiateOpenPosition(uint96(LONG_AMOUNT), CURRENT_PRICE, abi.encode(CURRENT_PRICE), "");
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
        uint256 initialTotalExpo = protocol.totalExpo();
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(uint96(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), "");
        Position memory tempPos = protocol.getLongPosition(tick, tickVersion, index);

        skip(oracleMiddleware.validationDelay() + 1);

        uint128 newPrice = CURRENT_PRICE + 100 ether;

        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(address(this), 0, newPrice, tick, tickVersion, index);
        protocol.validateOpenPosition(abi.encode(newPrice), "");

        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(pos.user, tempPos.user, "user");
        assertEq(pos.timestamp, tempPos.timestamp, "timestamp");
        assertEq(pos.amount, tempPos.amount, "amount");
        // price increased -> leverage decreased
        assertLt(pos.leverage, tempPos.leverage, "leverage");

        uint256 posTotalExpo = LONG_AMOUNT * pos.leverage / uint256(10) ** protocol.LEVERAGE_DECIMALS();
        assertEq(protocol.totalExpoByTick(tick), posTotalExpo, "total expo in tick");
        assertEq(protocol.totalExpo(), initialTotalExpo + posTotalExpo, "total expo");
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
        protocol.initiateOpenPosition{ value: 0.5 ether }(uint96(LONG_AMOUNT), 1000 ether, priceData, "");
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    // test refunds
    receive() external payable { }
}
