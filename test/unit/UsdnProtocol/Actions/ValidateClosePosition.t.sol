// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { ADMIN, DEPLOYER, USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The initiate close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 * @custom:and a validated long position of 1 ether with 10x leverage.
 */
contract TestUsdnProtocolActionsValidateClosePosition is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    struct TestData {
        bytes priceData;
        Position pos;
        uint24 liquidationPenalty;
        uint256 assetBalanceBefore;
        uint256 longBalanceStart;
        uint128 amountToClose;
        LongPendingAction action;
        uint128 liquidationPrice;
        uint256 vaultBalanceBefore;
        uint256 longBalanceBefore;
        uint128 liqPriceWithoutPenalty;
        int256 remainingValue;
        uint256 remainingToTransfer;
        uint256 totalPositionsBefore;
    }

    uint128 private constant POSITION_AMOUNT = 1 ether;
    int24 private initialTick;
    PositionId private posId;
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        initialTick = protocol.getHighestPopulatedTick();

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

    /**
     * @custom:scenario A user tries to validate a close position action with the wrong action pending
     * @custom:given An initiated open position
     * @custom:when The owner of the position calls _validateClosePosition
     * @custom:then The call reverts because the pending action is not ValidateClosePosition
     */
    function test_RevertWhen_validateClosePositionWithTheWrongPendingAction() public {
        // Setup an initiate action to have a pending validate action for this user
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        bytes memory priceData = abi.encode(params.initialPrice);

        // Try to validate a close position action with a pending action other than ValidateClosePosition
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidPendingAction.selector));
        protocol.i_validateClosePosition(payable(address(this)), priceData);
    }

    /**
     * @custom:scenario The user validates a close position pending action that has a different validator
     * @custom:given A pending action of type ValidateClosePosition
     * @custom:and With a validator that is not the caller saved at the caller's address
     * @custom:when The user calls validateClosePosition
     * @custom:then The protocol reverts with a UsdnProtocolInvalidPendingAction error
     */
    function test_RevertWhen_validateClosePositionWithWrongValidator() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice * 2 / 3,
                price: params.initialPrice
            })
        );

        // update the pending action to put another validator
        (PendingAction memory pendingAction, uint128 rawIndex) = protocol.i_getPendingAction(address(this));
        pendingAction.validator = address(1);

        protocol.i_clearPendingAction(address(this), rawIndex);
        protocol.i_addPendingAction(address(this), pendingAction);

        bytes memory priceData = abi.encode(params.initialPrice);

        vm.expectRevert(UsdnProtocolInvalidPendingAction.selector);
        protocol.i_validateClosePosition(payable(address(this)), priceData);
    }

    /**
     * @custom:scenario A user validates closes a position but sends too much ether
     * @custom:given A validated long position
     * @custom:and oracle validation cost == 0
     * @custom:when User calls validateClosePosition with an amount of ether greater than the validation cost
     * @custom:then The protocol refunds the amount sent
     */
    function test_validateClosePositionRefundExcessEther() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        uint256 etherBalanceBefore = address(this).balance;

        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateClosePosition{ value: 1 ether }(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            etherBalanceBefore,
            address(this).balance,
            "The sent ether should have been refunded as none of it was spent"
        );
    }

    /**
     * @custom:scenario A user validates closes a position with a pending action
     * @custom:given A validated long position
     * @custom:and an initiated open position action from another user
     * @custom:when User calls validateClosePosition with valid price data for the pending action
     * @custom:then The user validates the pending action
     */
    function test_validateClosePositionValidatePendingAction() public {
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

        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        skip(protocol.getLowLatencyValidatorDeadline());

        bytes[] memory previousData = new bytes[](1);
        previousData[0] = priceData;
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 1;

        vm.expectEmit(true, true, false, false);
        emit ValidatedOpenPosition(USER_1, USER_1, 0, 0, PositionId(0, 0, 0));
        protocol.validateClosePosition(payable(address(this)), priceData, PreviousActionsData(previousData, rawIndices));
    }

    /**
     * @custom:scenario A user validates closes a position
     * @custom:given A validated long position
     * @custom:when User calls validateClosePosition
     * @custom:then The user validate his initiated close position action
     */
    function test_validateClosePosition() public {
        bytes memory priceData = abi.encode(params.initialPrice);
        protocol.initiateClosePosition(
            posId,
            POSITION_AMOUNT,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        bytes32 actionId = oracleMiddleware.lastActionId();

        _waitDelay();

        vm.expectEmit(true, true, false, false);
        emit ValidatedClosePosition(address(this), address(this), posId, POSITION_AMOUNT, -1);
        bool success = protocol.validateClosePosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);
        assertTrue(success, "success");
        assertEq(oracleMiddleware.lastActionId(), actionId, "middleware action ID");
    }

    /* -------------------------------------------------------------------------- */
    /*                           _validateClosePosition                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user validates a close position action
     * @custom:given A validated open position of 1 wsteth
     * @custom:when The user validates the close of the position
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receives the position amount
     */
    function test_internalValidateClosePosition() public {
        _internalValidateClosePositionScenario(address(this), address(this));
    }

    /**
     * @custom:scenario The user validates a close position action for another recipient
     * @custom:given A validated open position of 1 wsteth
     * @custom:when The user validates the close of the position with another recipient
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the recipient receives the position amount
     */
    function test_internalValidateClosePositionForAnotherUser() public {
        _internalValidateClosePositionScenario(USER_1, address(this));
    }

    /**
     * @custom:scenario The validator validates a close position action for another owner
     * @custom:given A validated open position of 1 wsteth
     * @custom:when The validator validates the close of the position for another owner
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the recipient receives the position amount
     */
    function test_internalValidateClosePositionDifferentValidator() public {
        _internalValidateClosePositionScenario(address(this), USER_1);
    }

    /**
     * @custom:scenario The validator validates a close position action for another recipient and another owner
     * @custom:given A validated open position of 1 wsteth
     * @custom:when The validator validates the close of the position with another recipient
     * @custom:and The validator validates the close of the position for another owner
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the recipient receives the position amount
     */
    function test_internalValidateClosePositionForAnotherUserDifferentValidator() public {
        _internalValidateClosePositionScenario(USER_1, USER_2);
    }

    function _internalValidateClosePositionScenario(address to, address validator) internal {
        uint128 price = params.initialPrice;
        bytes memory priceData = abi.encode(price);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos, uint24 liquidationPenalty) = protocol.getLongPosition(posId);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(to);
        protocol.initiateClosePosition(
            posId, POSITION_AMOUNT, DISABLE_MIN_PRICE, to, payable(validator), priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(validator));
        uint128 totalExpoToClose = FixedPointMathLib.fullMulDiv(pos.totalExpo, POSITION_AMOUNT, pos.amount).toUint128();

        uint256 expectedAmountReceived = protocol.i_assetToRemove(
            protocol.getBalanceLong(),
            price,
            protocol.i_getEffectivePriceForTick(
                protocol.i_calcTickWithoutPenalty(posId.tick, liquidationPenalty), action.liqMultiplier
            ),
            totalExpoToClose
        );

        vm.expectEmit();
        emit ValidatedClosePosition(validator, to, posId, expectedAmountReceived, -1);
        protocol.i_validateClosePosition(validator, priceData);

        /* ----------------------------- User's Balance ----------------------------- */
        assertApproxEqAbs(
            assetBalanceBefore + POSITION_AMOUNT,
            wstETH.balanceOf(to),
            1,
            "User should have received the amount to close approximately"
        );
    }

    /// @dev struct to hold the test data to avoid "stack too deep"
    struct InternalValidatePartialClosePosition {
        bytes priceData;
        Position pos;
        uint256 assetBalanceBefore;
        uint128 amountToClose;
        Position posBefore;
        uint24 liquidationPenalty;
        LongPendingAction action;
        uint128 totalExpoToClose;
        uint256 expectedAmountReceived;
        int256 expectedProfit;
        Position posAfter;
    }

    /**
     * @custom:scenario Validate a partial close of a position
     * @custom:given A validated open position
     * @custom:and the initiate position is already done for half of the position
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receives half of the position amount
     */
    function test_internalValidatePartialClosePosition() public {
        InternalValidatePartialClosePosition memory data;

        data.priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (data.pos,) = protocol.getLongPosition(posId);
        data.assetBalanceBefore = protocol.getAsset().balanceOf(address(this));
        data.amountToClose = 100_000;
        protocol.initiateClosePosition(
            posId,
            data.amountToClose,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            data.priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        (data.posBefore, data.liquidationPenalty) = protocol.getLongPosition(posId);
        data.action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        data.totalExpoToClose =
            FixedPointMathLib.fullMulDiv(data.pos.totalExpo, data.amountToClose, data.pos.amount).toUint128();
        data.expectedAmountReceived = protocol.i_assetToRemove(
            protocol.getBalanceLong(),
            params.initialPrice,
            protocol.i_getEffectivePriceForTick(
                protocol.i_calcTickWithoutPenalty(posId.tick, data.liquidationPenalty), data.action.liqMultiplier
            ),
            data.totalExpoToClose
        );
        data.expectedProfit = int256(data.expectedAmountReceived) - int256(uint256(data.amountToClose));

        // Sanity Check
        // If user is address(0), the position was deleted from the tick array
        assertEq(data.posBefore.user, address(this), "The position should not have been deleted");

        vm.expectEmit();
        emit ValidatedClosePosition(
            address(this), address(this), posId, data.expectedAmountReceived, data.expectedProfit
        );
        protocol.i_validateClosePosition(address(this), data.priceData);

        /* ---------------------------- Position's state ---------------------------- */
        (data.posAfter,) = protocol.getLongPosition(posId);
        assertEq(data.posBefore.user, data.posAfter.user, "The user of the position should not have changed");
        assertEq(
            data.posBefore.timestamp, data.posAfter.timestamp, "Timestamp of the position should have stayed the same"
        );
        assertEq(
            data.posBefore.totalExpo,
            data.posAfter.totalExpo,
            "The total expo should not have changed after the validation"
        );
        assertEq(data.posBefore.amount, data.posAfter.amount, "The amount should not have changed after the validation");

        /* ----------------------------- User's Balance ----------------------------- */
        assertApproxEqAbs(
            data.assetBalanceBefore + data.amountToClose,
            wstETH.balanceOf(address(this)),
            1,
            "User should have received approximately the amount to close"
        );

        /* --------------------- Close the rest of the position --------------------- */
        protocol.initiateClosePosition(
            posId,
            data.pos.amount - data.amountToClose,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            data.priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        data.action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        data.expectedAmountReceived = protocol.i_assetToRemove(
            protocol.getBalanceLong(),
            params.initialPrice,
            protocol.i_getEffectivePriceForTick(
                protocol.i_calcTickWithoutPenalty(posId.tick, data.liquidationPenalty), data.action.liqMultiplier
            ),
            data.pos.totalExpo - data.totalExpoToClose
        );
        data.expectedProfit =
            int256(data.expectedAmountReceived) - int256(uint256(data.pos.amount - data.amountToClose));

        vm.expectEmit();
        emit ValidatedClosePosition(
            address(this), address(this), posId, data.expectedAmountReceived, data.expectedProfit
        );
        protocol.i_validateClosePosition(address(this), data.priceData);

        (data.posAfter,) = protocol.getLongPosition(posId);
        assertEq(data.posAfter.user, address(0), "The address should be 0x0 (position deleted)");
        assertEq(data.posAfter.amount, 0, "The amount should be 0");
        assertApproxEqAbs(
            data.assetBalanceBefore + data.pos.amount,
            wstETH.balanceOf(address(this)),
            2,
            "User should have received approximately his full amount back"
        );
    }

    /**
     * @custom:scenario Validate a partial close of a position that is losing money
     * @custom:given A validated open position
     * @custom:and The initiate close position is already done for half of the position
     * @custom:and The price dipped below the entry price before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receive parts of his funds back
     */
    function test_internalValidatePartialCloseUnderwaterPosition() public {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos, uint24 liquidationPenalty) = protocol.getLongPosition(posId);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        {
            uint128 amountToClose = pos.amount / 2;
            protocol.initiateClosePosition(
                posId,
                amountToClose,
                DISABLE_MIN_PRICE,
                address(this),
                payable(address(this)),
                priceData,
                EMPTY_PREVIOUS_DATA
            );
            _waitDelay();
        }

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 priceAfterInit = params.initialPrice - 50 ether;
        uint256 vaultBalanceBefore =
            uint256(protocol.vaultAssetAvailableWithFunding(priceAfterInit, uint128(block.timestamp)));
        uint256 longBalanceBefore =
            uint256(protocol.longAssetAvailableWithFunding(priceAfterInit, uint128(block.timestamp)));
        uint256 assetToTransfer = protocol.i_assetToRemove(
            protocol.getBalanceLong(),
            priceAfterInit,
            protocol.i_getEffectivePriceForTick(
                protocol.i_calcTickWithoutPenalty(action.tick, liquidationPenalty), action.liqMultiplier
            ),
            action.closePosTotalExpo
        );
        priceData = abi.encode(priceAfterInit);
        int256 pnl = int256(assetToTransfer) - int256(uint256(action.closeAmount));

        assertLt(pnl, 0, "User should have lost money on his position");

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), address(this), posId, assetToTransfer, pnl);
        protocol.i_validateClosePosition(address(this), priceData);

        assertEq(
            protocol.getAsset().balanceOf(address(this)),
            // pnl is a negative value
            assetBalanceBefore + uint256(int128(action.closeAmount) + pnl),
            "User should have received his assets minus his losses"
        );

        /* -------------------------- Balance Vault & Long -------------------------- */
        assertEq(
            protocol.getBalanceVault(),
            vaultBalanceBefore + (action.closeBoundedPositionValue - assetToTransfer),
            "Vault gets the difference"
        );
        assertEq(protocol.getBalanceLong(), longBalanceBefore, "Long balance does not change");
    }

    /**
     * @custom:scenario Validate a partial close of a position that just went in profit
     * @custom:given A validated open position
     * @custom:and The initiate close position is already done for half of the position
     * @custom:and The price increased above by 200$ before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receives his funds back + some profits
     */
    function test_internalValidatePartialClosePositionInProfit() public {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos, uint24 liquidationPenalty) = protocol.getLongPosition(posId);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        {
            uint128 amountToClose = pos.amount / 2;
            protocol.initiateClosePosition(
                posId,
                amountToClose,
                DISABLE_MIN_PRICE,
                address(this),
                payable(address(this)),
                priceData,
                EMPTY_PREVIOUS_DATA
            );
            _waitDelay();
        }

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 price = params.initialPrice + 200 ether;
        uint256 vaultBalanceBefore = uint256(protocol.vaultAssetAvailableWithFunding(price, uint128(block.timestamp)));
        uint256 longBalanceBefore = uint256(protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp)));
        uint256 assetToTransfer = protocol.i_assetToRemove(
            protocol.getBalanceLong(),
            price,
            protocol.i_getEffectivePriceForTick(
                protocol.i_calcTickWithoutPenalty(action.tick, liquidationPenalty), action.liqMultiplier
            ),
            action.closePosTotalExpo
        );
        priceData = abi.encode(price);
        int256 profits = int256(assetToTransfer - action.closeAmount);

        assertGt(profits, 0, "User should be in profits");

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), address(this), posId, assetToTransfer, profits);
        protocol.i_validateClosePosition(address(this), priceData);

        assertEq(
            protocol.getAsset().balanceOf(address(this)),
            assetBalanceBefore + action.closeAmount + uint256(profits),
            "User should have received his assets + profits"
        );

        /* -------------------------- Balance Vault & Long -------------------------- */
        assertEq(
            protocol.getBalanceVault(),
            vaultBalanceBefore - (assetToTransfer - action.closeBoundedPositionValue),
            "Balance of the vault should decrease to pay the missing profit"
        );
        assertEq(protocol.getBalanceLong(), longBalanceBefore, "Long balance should not change");
    }

    /**
     * @custom:scenario Validate a partial close of a position that should be liquidated
     * @custom:given A validated open position
     * @custom:and The initiate position is already done for half of the position
     * @custom:and The price dipped below its liquidation price before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a LiquidatedPosition event is emitted
     * @custom:and a LiquidatedTick event is emitted
     * @custom:and the user doesn't receive his funds back
     */
    function test_internalValidatePartialCloseLiquidatePosition() public {
        TestData memory data;
        data.priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (data.pos, data.liquidationPenalty) = protocol.getLongPosition(posId);
        data.assetBalanceBefore = protocol.getAsset().balanceOf(address(this));
        data.longBalanceStart = protocol.getBalanceLong();

        data.amountToClose = data.pos.amount / 2;
        protocol.initiateClosePosition(
            posId,
            data.amountToClose,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            data.priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        data.action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertEq(
            protocol.getBalanceLong(),
            data.longBalanceStart - data.action.closeBoundedPositionValue,
            "long balance decreased during initiate"
        );

        /* ------------------------- Validate Close Position ------------------------ */
        // we have no funding, the liq price should not change with time
        data.liquidationPrice = protocol.getEffectivePriceForTick(posId.tick);
        data.vaultBalanceBefore =
            uint256(protocol.vaultAssetAvailableWithFunding(data.liquidationPrice, uint128(block.timestamp)));
        data.longBalanceBefore =
            uint256(protocol.longAssetAvailableWithFunding(data.liquidationPrice, uint128(block.timestamp)));
        // value of the remaining part of the position (not being closed, but will be liquidated)
        data.liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            protocol.i_calcTickWithoutPenalty(data.action.tick, data.liquidationPenalty)
        );
        data.remainingValue = protocol.i_positionValue(
            data.liquidationPrice, data.liqPriceWithoutPenalty, data.pos.totalExpo - data.action.closePosTotalExpo
        );
        data.remainingToTransfer = protocol.i_assetToRemove(
            protocol.getBalanceLong(),
            data.liquidationPrice,
            data.liqPriceWithoutPenalty,
            data.pos.totalExpo - data.action.closePosTotalExpo
        );

        assertGt(data.remainingValue, 0, "remaining position value should be positive");
        assertEq(data.remainingToTransfer, uint256(data.remainingValue), "asset to transfer vs position value");
        data.totalPositionsBefore = protocol.getTotalLongPositions();
        data.priceData = abi.encode(data.liquidationPrice);

        // Make sure we liquidate the tick and the position at once
        vm.expectEmit(true, true, false, false);
        emit LiquidatedTick(posId.tick, posId.tickVersion, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit LiquidatedPosition(address(this), PositionId(0, 0, 0), 0, 0);
        protocol.i_validateClosePosition(address(this), data.priceData);

        assertEq(
            protocol.getAsset().balanceOf(address(this)),
            data.assetBalanceBefore,
            "User should not have received any asset"
        );

        /* -------------------------- Balance Vault & Long -------------------------- */
        assertEq(
            protocol.getBalanceVault(),
            data.vaultBalanceBefore + data.action.closeBoundedPositionValue + data.remainingToTransfer,
            "Full value of the position should have been transferred to the vault"
        );
        assertEq(
            protocol.getBalanceLong(),
            data.longBalanceBefore - data.remainingToTransfer,
            "Full value of the position should have been removed from the long side"
        );
        assertEq(
            protocol.getTotalLongPositions(), data.totalPositionsBefore - 1, "The position should have been removed"
        );
    }

    /**
     * @custom:scenario Validate a close of a position that should be liquidated
     * @custom:given A validated open position where the initiate close was already done at opening price
     * @custom:and The long balance was decreased by the value of the position that is being closed
     * @custom:when The price dips below the liquidation price
     * @custom:and The `validateClosePosition` is called with a price below liquidation
     * @custom:then The position is liquidated
     * @custom:and The user doesn't receive their funds back
     * @custom:and the vault receives any remaining collateral at the time of `initiateClosePosition`
     */
    function test_internalValidateCloseLiquidatePosition() public {
        // liquidate the position in setup, leaving only the deployer position
        _waitBeforeLiquidation();
        uint256 liquidated = protocol.mockLiquidate(abi.encode(7 * params.initialPrice / 10), 10);
        assertEq(liquidated, 1, "liquidated");

        bytes memory priceData = abi.encode(params.initialPrice);

        uint256 longBalanceBefore = protocol.getBalanceLong();

        /* ------------------------- Initiate Close Position ------------------------ */
        posId.tick = initialTick;
        posId.tickVersion = 0;
        posId.index = 0;
        (Position memory pos,) = protocol.getLongPosition(PositionId(posId.tick, 0, 0));
        vm.prank(DEPLOYER);
        protocol.initiateClosePosition(
            posId, pos.amount, DISABLE_MIN_PRICE, DEPLOYER, DEPLOYER, priceData, EMPTY_PREVIOUS_DATA
        );

        /* ----------------- Validate close position under liq price ---------------- */

        priceData = abi.encode(800 ether);
        skip(1 hours);

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(DEPLOYER));
        assertEq(
            protocol.getBalanceLong(), longBalanceBefore - action.closeBoundedPositionValue, "long balance decreased"
        );

        uint256 vaultBalanceBefore = protocol.getBalanceVault();

        // Make sure we liquidate the position
        vm.expectEmit(true, false, false, false);
        emit LiquidatedPosition(DEPLOYER, PositionId(0, 0, 0), 0, 0);
        protocol.i_validateClosePosition(DEPLOYER, priceData);

        assertEq(
            protocol.getBalanceVault(), vaultBalanceBefore + action.closeBoundedPositionValue, "final vault balance"
        );
    }

    /**
     * @custom:scenario A validate close position action liquidates a tick but is not validated because another tick
     * still needs to be liquidated
     * @custom:given Three positions with different ticks, the lowest of which was initiated for close
     * @custom:when The user with the lowest liq price position calls `validateClosePosition` function with a price
     * below the liquidation price of the two other positions
     * @custom:then One position is liquidated
     * @custom:and The user's close position action is not validated
     */
    function test_validateCloseWithPendingLiquidation() public {
        // below all current positions
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice / 4,
                price: params.initialPrice
            })
        );

        _waitMockMiddlewarePriceDelay();

        vm.prank(USER_1);
        bool success = protocol.validateClosePosition(USER_1, abi.encode(params.initialPrice / 3), EMPTY_PREVIOUS_DATA);
        assertFalse(success, "success");

        PendingAction memory pending = protocol.getUserPendingAction(USER_1);
        assertEq(
            uint256(pending.action),
            uint256(ProtocolAction.ValidateClosePosition),
            "user 1 pending action should not be cleared"
        );

        assertEq(
            posId.tickVersion + 1, protocol.getTickVersion(posId.tick), "setup position should have been liquidated"
        );
    }

    /**
     * @custom:scenario The user validates a close position action with a reentrancy attempt
     * @custom:given A validated open position with an initiated close action done
     * @custom:and a user being a smart contract that calls validateClosePosition with too much ether
     * @custom:and a receive() function that calls validateClosePosition again
     * @custom:when The user calls validateClosePosition again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_validateClosePositionCalledWithReentrancy() public {
        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.validateClosePosition(payable(address(this)), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
            return;
        }

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.validateClosePosition.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.validateClosePosition{ value: 1 }(
            payable(address(this)), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates and validates (after the validator deadline)
     * a close position action with another msg.sender
     * @custom:given The user initiated a closePosition
     * @custom:when The another user validates the closePosition
     * @custom:then The security deposit is refunded to the owner
     */
    function test_validateClosePositionEtherRefundToOwner() public {
        vm.prank(ADMIN);
        protocol.setSecurityDepositValue(0.5 ether);

        bytes memory priceData = abi.encode(params.initialPrice);
        uint256 balanceUserBefore = USER_1.balance;
        uint256 balanceContractBefore = address(this).balance;

        protocol.initiateClosePosition{ value: 0.5 ether }(
            posId, POSITION_AMOUNT, DISABLE_MIN_PRICE, USER_1, payable(address(this)), priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        vm.prank(USER_1);
        protocol.validateClosePosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertEq(USER_1.balance, balanceUserBefore, "validator balance after refund");
        assertEq(address(this).balance, balanceContractBefore, "contract balance after refund");
    }

    /**
     * @custom:scenario The user validate a close position with a paused protocol
     * @custom:given A user initiated close position
     * @custom:and A paused protocol
     * @custom:when The user calls validateClosePosition
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_validateClosePositionPaused() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        _pauseProtocol(ADMIN);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.validateClosePosition(payable(address(this)), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
    }

    /// @dev Allow refund tests
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_validateClosePositionCalledWithReentrancy();
            _reenter = false;
        }
    }
}
