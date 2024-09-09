// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

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

    struct ValueToCheckBefore {
        uint256 balance;
        uint256 protocolBalance;
        uint256 totalPositions;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
    }

    struct ExpectedValues {
        int24 expectedTick;
        uint256 expectedPosTotalExpo;
        uint256 expectedPosValue;
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
        _initiateOpenPositionScenario(address(this), address(this));
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
    function test_initiateOpenPositionForAnotherUser() public {
        _initiateOpenPositionScenario(USER_1, USER_1);
    }

    /**
     * @custom:scenario The user initiates an open position action with a different validator
     * @custom:given The amount of collateral is 1 wstETH and the current price is 2000$
     * @custom:when The user initiates an open position with 1 wstETH and a desired liquidation price of ~1333$
     * (approx 3x leverage) and a different validator
     * @custom:then The protocol creates the position and emits the InitiatedOpenPosition event
     * @custom:and the state changes are as expected
     */
    function test_initiateOpenPositionDifferentValidator() public {
        _initiateOpenPositionScenario(address(this), USER_1);
    }

    function _initiateOpenPositionScenario(address to, address validator) internal {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        ExpectedValues memory expected;
        expected.expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);
        uint128 liqPriceWithoutPenalty =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(expected.expectedTick));
        expected.expectedPosTotalExpo =
            protocol.i_calcPositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, liqPriceWithoutPenalty);
        expected.expectedPosValue =
            expected.expectedPosTotalExpo * (CURRENT_PRICE - liqPriceWithoutPenalty) / CURRENT_PRICE;

        // state before opening the position
        ValueToCheckBefore memory before = ValueToCheckBefore({
            balance: wstETH.balanceOf(address(this)),
            protocolBalance: wstETH.balanceOf(address(protocol)),
            totalPositions: protocol.getTotalLongPositions(),
            totalExpo: protocol.getTotalExpo(),
            balanceLong: uint256(protocol.i_longAssetAvailable(CURRENT_PRICE)),
            balanceVault: uint256(protocol.i_vaultAssetAvailable(CURRENT_PRICE))
        });

        vm.expectEmit();
        emit InitiatedOpenPosition(
            to,
            validator,
            uint40(block.timestamp),
            uint128(expected.expectedPosTotalExpo),
            uint128(LONG_AMOUNT),
            CURRENT_PRICE,
            PositionId(expected.expectedTick, 0, 0)
        );
        (bool success, PositionId memory posId) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            desiredLiqPrice,
            type(uint128).max,
            protocol.getMaxLeverage(),
            to,
            payable(validator),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success, "success");
        // timestamp is not critical as there is no funding
        int256 posValue = protocol.getPositionValue(posId, CURRENT_PRICE, uint128(block.timestamp));
        assertEq(uint256(posValue), expected.expectedPosValue, "pos value");

        // check state after opening the position
        assertEq(posId.tick, expected.expectedTick, "tick number");
        assertEq(posId.tickVersion, 0, "tick version");
        assertEq(posId.index, 0, "index");

        assertEq(wstETH.balanceOf(address(this)), before.balance - LONG_AMOUNT, "user wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), before.protocolBalance + LONG_AMOUNT, "protocol wstETH balance");
        assertEq(protocol.getTotalLongPositions(), before.totalPositions + 1, "total long positions");
        assertEq(protocol.getTotalExpo(), before.totalExpo + expected.expectedPosTotalExpo, "protocol total expo");
        TickData memory tickData = protocol.getTickData(expected.expectedTick);
        assertEq(tickData.totalExpo, expected.expectedPosTotalExpo, "total expo in tick");
        assertEq(tickData.totalPos, 1, "positions in tick");
        assertEq(
            protocol.getBalanceLong() + protocol.getBalanceVault(),
            before.balanceLong + before.balanceVault + LONG_AMOUNT,
            "total balance of protocol"
        );
        assertEq(protocol.getBalanceLong(), before.balanceLong + uint256(posValue), "balance long");

        // the pending action should not yet be actionable by a third party
        (PendingAction[] memory pendingActions,) = protocol.getActionablePendingActions(address(0));
        assertEq(pendingActions.length, 0, "no pending action");

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(validator));
        assertTrue(action.action == ProtocolAction.ValidateOpenPosition, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.to, to, "action to");
        assertEq(action.validator, validator, "action validator");
        assertEq(action.tick, expected.expectedTick, "action tick");
        assertEq(action.tickVersion, 0, "action tickVersion");
        assertEq(action.index, 0, "action index");

        // the pending action should be actionable after the validation deadline
        _waitBeforeActionablePendingAction();
        (pendingActions,) = protocol.getActionablePendingActions(address(0));
        action = protocol.i_toLongPendingAction(pendingActions[0]);
        assertEq(action.to, to, "pending action to");
        assertEq(action.validator, validator, "pending action validator");

        Position memory position;
        (position,) = protocol.getLongPosition(posId);
        assertFalse(position.validated, "pos validated");
        assertEq(position.user, to, "user position");
        assertEq(position.timestamp, action.timestamp, "timestamp position");
        assertEq(position.amount, uint128(LONG_AMOUNT), "amount position");
        assertEq(position.totalExpo, expected.expectedPosTotalExpo, "totalExpo position");

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
        uint24 originalLiqPenalty = protocol.getLiquidationPenalty();
        uint24 storedLiqPenalty = originalLiqPenalty - 1;

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
            protocol.i_calcPositionTotalExpo(uint128(LONG_AMOUNT), CURRENT_PRICE, expectedLiqPrice);

        // create position which ends up in the same tick
        (, PositionId memory posId2) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            desiredLiqPrice,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
        assertEq(posId.tick, posId2.tick, "tick is the same");
        (Position memory pos, uint24 liqPenalty) = protocol.getLongPosition(posId2);
        assertEq(pos.totalExpo, expectedTotalExpo, "total expo: stored penalty was used");
        assertEq(liqPenalty, storedLiqPenalty, "pos liquidation penalty");
    }

    /**
     * @custom:scenario A initiate open position liquidates a tick but is not initiated because another tick still
     * needs to be liquidated
     * @custom:given Two positions in different ticks
     * @custom:when The `initiateOpenPosition` function is called with a price below the liq price of both positions
     * @custom:then One of the positions is liquidated
     * @custom:and The new position isn't initiated
     * @custom:and The user wsteth balance does not change
     */
    function test_initiateOpenPositionIsPendingLiquidation() public {
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: uint128(LONG_AMOUNT),
                desiredLiqPrice: params.initialPrice - params.initialPrice / 5,
                price: params.initialPrice
            })
        );

        _waitMockMiddlewarePriceDelay();

        uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

        (bool success, PositionId memory posId) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            params.initialPrice / 10,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(params.initialPrice / 3),
            EMPTY_PREVIOUS_DATA
        );
        assertFalse(success, "success");
        assertEq(posId.tick, protocol.NO_POSITION_TICK(), "pos tick");

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user 0 should not have a pending action");

        assertEq(
            userPosId.tickVersion + 1,
            protocol.getTickVersion(userPosId.tick),
            "user 1 position should have been liquidated"
        );

        assertEq(wstethBalanceBefore, wstETH.balanceOf(address(this)), "user 0 wsteth balance should not change");
    }

    /**
     * @custom:scenario The user initiates an open position action with a zero amount
     * @custom:when The user initiates an open position with 0 wstETH
     * @custom:then The protocol reverts with UsdnProtocolZeroAmount
     */
    function test_RevertWhen_initiateOpenPositionZeroAmount() public {
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateOpenPosition(
            0,
            2000 ether,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with no recipient
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates an open position with the address to at zero
     * @custom:then The protocol reverts with UsdnProtocolInvalidAddressTo
     */
    function test_RevertWhen_zeroAddressTo() public {
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.initiateOpenPosition(
            1 ether,
            2000 ether,
            type(uint128).max,
            leverage,
            address(0),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with parameter validator defined at zero
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates an open position with the address validator at zero
     * @custom:then The protocol reverts with UsdnProtocolInvalidAddressValidator
     */
    function test_RevertWhen_zeroAddressValidator() public {
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(UsdnProtocolInvalidAddressValidator.selector);
        protocol.initiateOpenPosition(
            1 ether,
            2000 ether,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(0)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with a leverage that's too low
     * @custom:when The user initiates an open position with a desired liquidation price of $0.0000000000001
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooLow
     */
    function test_RevertWhen_initiateOpenPositionLowLeverage() public {
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(UsdnProtocolLeverageTooLow.selector);
        protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            100_000,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
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

        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(UsdnProtocolLeverageTooHigh.selector);
        protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            desiredLiqPrice,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
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

        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolLiquidationPriceSafetyMargin.selector, expectedLiqPrice, expectedMaxLiqPrice
            )
        );
        protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            CURRENT_PRICE,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
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
        protocol.initiateOpenPosition(
            1 ether,
            1000 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
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
            uint128(LONG_AMOUNT),
            1000 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The user initiates an open position action with an entry price less than the user's max price
     * @custom:given The current price is $2000
     * @custom:when The user initiates an open position with a userMaxPrice of $1999
     * @custom:then The protocol reverts with UsdnProtocolSlippageMaxPriceExceeded
     */
    function test_RevertWhen_initiateOpenPositionWithEntryPriceLessThanUserMaxPrice() public {
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(UsdnProtocolSlippageMaxPriceExceeded.selector);
        protocol.initiateOpenPosition(
            1 ether,
            2000 ether,
            CURRENT_PRICE - 1,
            leverage,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
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
            uint256 leverage = protocol.getMaxLeverage();
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.initiateOpenPosition(
                1 ether,
                1500 ether,
                type(uint128).max,
                leverage,
                address(this),
                payable(address(this)),
                NO_PERMIT2,
                abi.encode(CURRENT_PRICE),
                EMPTY_PREVIOUS_DATA
            );
            return;
        }

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.initiateOpenPosition.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateOpenPosition{ value: 1 }(
            1 ether,
            1500 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with a calculated leverage greater than expected
     * leverage
     * @custom:given The user initiates an open position with a calculated leverage of 4 but he want a expected leverage
     * of 2
     * @custom:when The user initiates an open position with a calculated leverage of 4 and gives inputs
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooHigh
     */
    function test_RevertWhen_initiateOpenPositionLeverageLowerThanExpected() public {
        vm.expectRevert(UsdnProtocolLeverageTooHigh.selector);
        protocol.initiateOpenPosition(
            1 ether,
            1500 ether,
            type(uint128).max,
            2 * 10 ** Constants.LEVERAGE_DECIMALS,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
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
