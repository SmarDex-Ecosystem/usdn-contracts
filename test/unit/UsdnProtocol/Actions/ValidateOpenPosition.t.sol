// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

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
        uint256 initialLongBalance;
        uint256 initialVaultBalance;
        int256 longBalanceWithoutPos;
        uint128 validatePrice;
        int24 validateTick;
        uint8 originalLiqPenalty;
        PositionId tempPosId;
        uint256 validateTickVersion;
        uint256 validateIndex;
        uint256 expectedLeverage;
        uint256 expectedPosValue;
    }

    struct InitialData {
        uint256 initialLongBalance;
        uint256 initialVaultBalance;
        uint256 initialTotalExpo;
    }

    struct ExpectedData {
        int256 expectedLongBalanceWithoutPos;
        uint128 expectedLiqPrice;
        uint128 expectedPosTotalExpo;
        uint256 expectedPosValue;
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
        _validateOpenPositionScenario(address(this), address(this));
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
        _validateOpenPositionScenario(USER_1, USER_1);
    }

    /**
     * @custom:scenario The user validates an open position action with a different validator
     * @custom:given The user has initiated an open position with 1 wstETH and a desired liquidation price of ~1333$
     * @custom:and the price was 2000$ at the moment of initiation
     * @custom:and the price has increased to 2100$
     * @custom:when The user validates the open position with the new price
     * @custom:then The owner of the position is the previously defined user
     */
    function test_validateOpenPositionDifferentValidator() public {
        _validateOpenPositionScenario(address(this), USER_1);
    }

    /**
     * @custom:scenario A validate open position liquidates a tick but is not validated because another tick still
     * needs to be liquidated
     * @custom:given The deployer position and another user position which was only initiated
     * @custom:when The `validateOpenPosition` function is called by the user with a price below the liq price of both
     * positions
     * @custom:then The deployer's tick is liquidated
     * @custom:and The open action isn't validated because the user's position still needs to be liquidated
     */
    function test_validateOpenPositionWithPendingLiquidation() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: uint128(LONG_AMOUNT),
                desiredLiqPrice: params.initialPrice / 3,
                price: params.initialPrice
            })
        );

        _waitMockMiddlewarePriceDelay();

        bool success = protocol.validateOpenPosition(
            payable(address(this)), abi.encode(params.initialPrice / 4), EMPTY_PREVIOUS_DATA
        );
        assertFalse(success, "success");

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        assertEq(
            uint256(pending.action),
            uint256(ProtocolAction.ValidateOpenPosition),
            "user 0 pending action should not have been cleared"
        );

        assertEq(
            initialPosition.tickVersion + 1,
            protocol.getTickVersion(initialPosition.tick),
            "deployer position should have been liquidated"
        );
    }

    /**
     * @custom:scenario A validate open position liquidates itself
     * @custom:given The user has initiated an open position
     * @custom:when The `validateOpenPosition` function is called with a price below the liq price
     * @custom:then The position is liquidated
     * @custom:and The pending action is cleared
     */
    function test_validateOpenPositionWasLiquidated() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: uint128(LONG_AMOUNT),
                desiredLiqPrice: params.initialPrice * 4 / 5,
                price: params.initialPrice
            })
        );

        _waitMockMiddlewarePriceDelay();

        protocol.validateOpenPosition(
            payable(address(this)), abi.encode(params.initialPrice * 2 / 3), EMPTY_PREVIOUS_DATA
        );

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        assertEq(
            uint256(pending.action), uint256(ProtocolAction.None), "user 0 pending action should have been cleared"
        );
        assertEq(
            posId.tickVersion + 1, protocol.getTickVersion(posId.tick), "user 0 position should have been liquidated"
        );
    }

    function _validateOpenPositionScenario(address to, address validator) internal {
        InitialData memory initialData = InitialData({
            initialLongBalance: protocol.getBalanceLong(),
            initialVaultBalance: protocol.getBalanceVault(),
            initialTotalExpo: protocol.getTotalExpo()
        });
        uint128 newPrice = CURRENT_PRICE + 100 ether;
        ExpectedData memory expected;
        expected.expectedLongBalanceWithoutPos = protocol.i_longAssetAvailable(newPrice);

        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        (, PositionId memory posId) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            desiredLiqPrice,
            to,
            payable(validator),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
        (Position memory tempPos,) = protocol.getLongPosition(posId);
        bytes32 actionId = oracleMiddleware.lastActionId();

        _waitDelay();

        expected.expectedLiqPrice = protocol.getEffectivePriceForTick(
            protocol.i_calcTickWithoutPenalty(posId.tick),
            uint256(newPrice),
            uint256(
                protocol.longTradingExpoWithFunding(
                    newPrice, tempPos.timestamp + uint128(oracleMiddleware.getValidationDelay())
                )
            ),
            protocol.getLiqMultiplierAccumulator()
        );
        expected.expectedPosTotalExpo =
            protocol.i_calcPositionTotalExpo(tempPos.amount, newPrice, expected.expectedLiqPrice);
        expected.expectedPosValue =
            uint256(expected.expectedPosTotalExpo) * (newPrice - expected.expectedLiqPrice) / newPrice;

        vm.expectEmit();
        emit ValidatedOpenPosition(to, validator, expected.expectedPosTotalExpo, newPrice, posId);
        bool success = protocol.validateOpenPosition(payable(validator), abi.encode(newPrice), EMPTY_PREVIOUS_DATA);
        assertTrue(success, "success");
        int256 posValue = protocol.getPositionValue(posId, newPrice, uint128(block.timestamp));
        assertEq(uint256(posValue), expected.expectedPosValue, "pos value");

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertTrue(pos.validated, "validated");
        assertEq(pos.user, tempPos.user, "user");
        assertEq(pos.amount, tempPos.amount, "amount");
        assertEq(pos.timestamp, tempPos.timestamp, "timestamp");
        // price increased -> total expo decreased
        assertLt(pos.totalExpo, tempPos.totalExpo, "totalExpo should have decreased");
        assertEq(pos.totalExpo, expected.expectedPosTotalExpo, "totalExpo");

        TickData memory tickData = protocol.getTickData(posId.tick);
        assertEq(tickData.totalExpo, pos.totalExpo, "total expo in tick");
        assertEq(protocol.getTotalExpo(), initialData.initialTotalExpo + pos.totalExpo, "total expo");
        assertEq(oracleMiddleware.lastActionId(), actionId, "middleware action ID");
        assertEq(
            protocol.getBalanceLong() + protocol.getBalanceVault(),
            initialData.initialLongBalance + initialData.initialVaultBalance + LONG_AMOUNT,
            "total balance"
        );
        assertEq(
            protocol.getBalanceLong(),
            uint256(expected.expectedLongBalanceWithoutPos) + uint256(posValue),
            "long balance"
        );
    }

    /**
     * @custom:scenario The user validates an open position action with a price that increases the leverage above the
     * max leverage
     * @custom:given The user has initiated an open position with 1 wstETH and a desired liquidation price of ~1800$
     * @custom:and the price was 2000$ at the moment of initiation
     * @custom:and the price has decreased to 1900$
     * @custom:when The user validates the open position with the new price
     * @custom:then The protocol validates the position and emits the ValidatedOpenPosition event
     * @custom:and the position is stays in the same tick
     * @custom:and the position's leverage exceeds the max leverage
     */
    function test_validateOpenPositionAboveMaxLeverage() public {
        TestData memory testData;
        testData.initialLongBalance = protocol.getBalanceLong();
        testData.initialVaultBalance = protocol.getBalanceVault();
        testData.validatePrice = CURRENT_PRICE - 100 ether;
        testData.longBalanceWithoutPos = protocol.i_longAssetAvailable(testData.validatePrice);

        int24 liqPenalty = int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        // leverage approx 10x
        (, PositionId memory posId) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            CURRENT_PRICE * 9 / 10,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
        (Position memory tempPos,) = protocol.getLongPosition(posId);

        _waitDelay();

        uint128 expectedLiqPrice = protocol.getEffectivePriceForTick(
            posId.tick - liqPenalty,
            uint256(testData.validatePrice),
            uint256(
                protocol.longTradingExpoWithFunding(
                    testData.validatePrice, tempPos.timestamp + uint128(oracleMiddleware.getValidationDelay())
                )
            ),
            protocol.getLiqMultiplierAccumulator()
        );
        uint128 expectedPosTotalExpo =
            protocol.i_calcPositionTotalExpo(tempPos.amount, testData.validatePrice, expectedLiqPrice);
        testData.expectedPosValue =
            uint256(expectedPosTotalExpo) * (testData.validatePrice - expectedLiqPrice) / testData.validatePrice;
        uint256 expectedLeverage = protocol.i_getLeverage(testData.validatePrice, expectedLiqPrice);

        vm.expectEmit();
        emit ValidatedOpenPosition(address(this), address(this), expectedPosTotalExpo, testData.validatePrice, posId);
        protocol.validateOpenPosition(payable(address(this)), abi.encode(testData.validatePrice), EMPTY_PREVIOUS_DATA);

        int256 posValue = protocol.getPositionValue(posId, testData.validatePrice, uint128(block.timestamp));
        assertEq(uint256(posValue), testData.expectedPosValue, "pos value");
        assertGt(expectedLeverage, uint128(10 * 10 ** protocol.LEVERAGE_DECIMALS()), "final leverage");
        assertEq(
            protocol.getBalanceLong() + protocol.getBalanceVault(),
            testData.initialLongBalance + testData.initialVaultBalance + LONG_AMOUNT,
            "total balance"
        );
        assertEq(protocol.getBalanceLong(), uint256(testData.longBalanceWithoutPos) + uint256(posValue), "long balance");
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
        PositionId memory posId = _createStalePendingActionHelper();

        bytes memory priceData = abi.encode(uint128(1500 ether));
        // validating the action emits the proper event
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.validateOpenPosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);
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
            protocol.validateOpenPosition(payable(address(this)), abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);
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
        protocol.validateOpenPosition{ value: 1 }(
            payable(address(this)), abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario A user tries to validate an open position action with the wrong pending action
     * @custom:given An initiated close position action
     * @custom:when The owner of the position calls validateOpenPosition
     * @custom:then The call reverts because the pending action is not of type ValidateOpenPosition
     */
    function test_RevertWhen_validateOpenPositionWithTheWrongPendingAction() public {
        // Setup an initiate action to have a pending validate action for this user
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: 1 ether,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice / 2,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidPendingAction.selector));
        protocol.i_validateOpenPosition(payable(address(this)), abi.encode(CURRENT_PRICE));
    }

    /**
     * @custom:scenario The user validates an open position pending action that has a different validator
     * @custom:given A pending action that of type ValidateOpenPosition
     * @custom:and With a validator that is not the caller saved at the caller's address
     * @custom:when The user calls validateOpenPosition
     * @custom:then The protocol reverts with a UsdnProtocolInvalidPendingAction error
     */
    function test_RevertWhen_validateOpenPositionWithWrongValidator() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: uint128(LONG_AMOUNT),
                desiredLiqPrice: CURRENT_PRICE * 2 / 3,
                price: CURRENT_PRICE
            })
        );

        // update the pending action to put another validator
        (PendingAction memory pendingAction, uint128 rawIndex) = protocol.i_getPendingAction(address(this));
        pendingAction.validator = address(1);

        protocol.i_clearPendingAction(address(this), rawIndex);
        protocol.i_addPendingAction(address(this), pendingAction);

        vm.expectRevert(UsdnProtocolInvalidPendingAction.selector);
        protocol.i_validateOpenPosition(payable(address(this)), abi.encode(CURRENT_PRICE));
    }

    /**
     * @custom:scenario The user initiates and validates (after the validationDeadline)
     * an openPosition action with another validator
     * @custom:given The user initiated an openPosition with 1 wstETH and a desired liquidation price of ~1333$
     * @custom:and we wait until the validation deadline is passed
     * @custom:when The user validates the openPosition
     * @custom:then The security deposit is refunded to the validator
     */
    function test_validateOpenPositionEtherRefundToValidator() public {
        vm.startPrank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees
        protocol.setSecurityDepositValue(0.5 ether);
        vm.stopPrank();

        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x

        uint64 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 balanceUserBefore = USER_1.balance;
        uint256 balanceContractBefore = address(this).balance;

        protocol.initiateOpenPosition{ value: 0.5 ether }(
            uint128(LONG_AMOUNT),
            desiredLiqPrice,
            address(this),
            USER_1,
            NO_PERMIT2,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();
        protocol.validateOpenPosition(USER_1, abi.encode(CURRENT_PRICE), EMPTY_PREVIOUS_DATA);

        assertEq(USER_1.balance, balanceUserBefore + securityDepositValue, "validator balance after refund");
        assertEq(address(this).balance, balanceContractBefore - securityDepositValue, "contract balance after refund");
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
