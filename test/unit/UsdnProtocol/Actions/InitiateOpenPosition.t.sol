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

    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

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
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA
        );
        uint256 tickLiqPrice = protocol.getEffectivePriceForTick(
            tick - int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing()
        );

        // check state after opening the position
        assertEq(tick, expectedTick, "tick number");
        assertEq(tickVersion, 0, "tick version");
        assertEq(index, 0, "index");

        assertEq(wstETH.balanceOf(address(this)), balanceBefore - LONG_AMOUNT, "user wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), protocolBalanceBefore + LONG_AMOUNT, "protocol wstETH balance");
        assertEq(protocol.getTotalLongPositions(), totalPositionsBefore + 1, "total long positions");
        {
            uint256 positionExpo =
                protocol.i_calculatePositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, uint128(tickLiqPrice));
            assertEq(protocol.getTotalExpo(), totalExpoBefore + positionExpo, "protocol total expo");
            TickData memory tickData = protocol.getTickData(expectedTick);
            assertEq(tickData.totalExpo, positionExpo, "total expo in tick");
            assertEq(tickData.totalPos, 1, "positions in tick");
        }
        assertEq(protocol.getBalanceLong(), balanceLongBefore + LONG_AMOUNT, "balance of long side");

        // the pending action should not yet be actionable by a third party
        (PendingAction[] memory pendingActions,) = protocol.getActionablePendingActions(address(0));
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
        (pendingActions,) = protocol.getActionablePendingActions(address(0));
        action = protocol.i_toLongPendingAction(pendingActions[0]);
        assertEq(action.user, address(this), "pending action user");
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
            USER_1, ProtocolAction.ValidateOpenPosition, uint128(LONG_AMOUNT), desiredLiqPrice, CURRENT_PRICE
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
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA
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
        protocol.initiateOpenPosition(0, 2000 ether, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates an open position action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls initiateOpenPosition when receiving ether
     * @custom:and A receive() function that calls initiateOpenPosition again
     * @custom:when The user calls initiateOpenPosition with some ether to trigger a refund
     * @custom:then The protocol reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_initiateOpenPositionCalledWithReentrancy() public {
        _reenter = true;

        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateOpenPosition{ value: 1 }(1 ether, 1500 ether, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates an open position action with a leverage that's too low
     * @custom:when The user initiates an open position with a desired liquidation price of $0.0000000000001
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooLow
     */
    function test_RevertWhen_initiateOpenPositionLowLeverage() public {
        vm.expectRevert(UsdnProtocolLeverageTooLow.selector);
        protocol.initiateOpenPosition(uint128(LONG_AMOUNT), 100_000, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);
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
            uint128(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA
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
            uint128(LONG_AMOUNT), CURRENT_PRICE, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA
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
        (int24 tick, uint256 tickVersion, uint256 index) = _createStalePendingActionHelper();

        wstETH.approve(address(protocol), 1 ether);
        bytes memory priceData = abi.encode(uint128(1500 ether));
        // we should be able to open a new position
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, EMPTY_PREVIOUS_DATA);
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
            uint128(LONG_AMOUNT), 1000 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.initiateOpenPosition(1 ether, 1500 ether, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);
        }
    }
}
