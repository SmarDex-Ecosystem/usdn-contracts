// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN, USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction, Position, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The validateOpenPosition function of the UsdnProtocolActions contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsValidateOpenPosition is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint256 internal constant LONG_AMOUNT = 1 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;

    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    struct TestData {
        uint128 validatePrice;
        int24 validateTick;
        uint8 originalLiqPenalty;
        int24 tempTick;
        uint256 tempTickVersion;
        uint256 tempIndex;
        uint256 validateTickVersion;
        uint256 validateIndex;
        uint128 expectedLeverage;
    }

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableProtocolFees = false;
        params.flags.enableFunding = false;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
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

        vm.expectEmit(true, true, false, false);
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
        int24 newTick = protocol.getEffectiveTickForPrice(
            newLiqPrice,
            newPrice,
            uint256(protocol.i_longTradingExpo(newPrice)),
            protocol.getLiqMultiplierAccumulator(),
            protocol.getTickSpacing()
        ) + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        int256 longBalanceBefore = protocol.longAssetAvailableWithFunding(newPrice, uint128(block.timestamp - 1));
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
        assertEq(protocol.getBalanceLong(), uint256(longBalanceBefore), "balance of long side unchanged");
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
        TestData memory data;
        uint128 desiredLiqPrice = CURRENT_PRICE * 9 / 10; // leverage approx 10x
        uint8 originalLiqPenalty = protocol.getLiquidationPenalty();
        uint8 storedLiqPenalty = originalLiqPenalty - 1;

        // calculate the future expected tick for the position we will validate later
        data.validatePrice = CURRENT_PRICE - 100 ether;
        data.validateTick = protocol.getEffectiveTickForPrice(
            protocol.i_getLiquidationPrice(data.validatePrice, uint128(protocol.getMaxLeverage())),
            data.validatePrice,
            uint256(protocol.i_longTradingExpo(data.validatePrice)),
            protocol.getLiqMultiplierAccumulator(),
            protocol.getTickSpacing()
        ) + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();

        data.originalLiqPenalty = protocol.getLiquidationPenalty();
        // open another user position to set the tick's penalty to a lower value in storage
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(data.originalLiqPenalty - 1);
        (int24 otherTick,,) = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: uint128(LONG_AMOUNT),
                desiredLiqPrice: protocol.getEffectivePriceForTick(data.validateTick),
                price: CURRENT_PRICE
            })
        );
        assertEq(otherTick, data.validateTick, "both positions in same tick");

        // restore liquidation penalty to original value
        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(data.originalLiqPenalty);

        // initiate deposit with leverage close to 10x
        (data.tempTick, data.tempTickVersion, data.tempIndex) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT), CURRENT_PRICE * 9 / 10, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA, address(this)
        );

        _waitDelay();

        // expected values
        data.validateTickVersion = protocol.getTickVersion(data.validateTick);
        data.validateIndex = protocol.getTickData(data.validateTick).totalPos;
        data.expectedLeverage = protocol.i_getLeverage(
            data.validatePrice,
            protocol.getEffectivePriceForTick(
                data.validateTick - int24(uint24(data.originalLiqPenalty - 1)) * protocol.getTickSpacing(),
                data.validatePrice,
                uint256(protocol.i_longTradingExpo(data.validatePrice)),
                protocol.getLiqMultiplierAccumulator()
            )
        );
        // final leverage should be above 10x because of the stored liquidation penalty of the target tick
        assertGt(data.expectedLeverage, uint128(10 * 10 ** protocol.LEVERAGE_DECIMALS()), "final leverage");

        // validate deposit with a lower entry price
        vm.expectEmit();
        emit LiquidationPriceUpdated(
            data.tempTick,
            data.tempTickVersion,
            data.tempIndex,
            data.validateTick,
            data.validateTickVersion,
            data.validateIndex
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(
            address(this),
            address(this),
            data.expectedLeverage,
            data.validatePrice,
            data.validateTick,
            data.validateTickVersion,
            data.validateIndex
        );
        protocol.validateOpenPosition(abi.encode(data.validatePrice), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user validates an open position action with reentrancy attempt
     * @custom:given A user being a smart contract that calls validateOpenPosition when receiving ether
     * @custom:and A receive() function that calls validateOpenPosition again
     * @custom:when The user calls validateOpenPosition with some ether to trigger a refund
     * @custom:then The protocol reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_validateOpenPositionCalledWithReentrancy() public {
        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.validateOpenPosition(abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);
            return;
        }

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: uint128(LONG_AMOUNT),
                desiredLiqPrice: CURRENT_PRICE * 2 / 3,
                price: CURRENT_PRICE
            })
        );

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.validateOpenPosition.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.validateOpenPosition{ value: 1 }(abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_validateOpenPositionCalledWithReentrancy();
            _reenter = false;
        }
    }
}
