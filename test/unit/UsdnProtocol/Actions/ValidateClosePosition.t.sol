// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import {
    LongPendingAction,
    PendingAction,
    Position,
    ProtocolAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1, DEPLOYER } from "test/utils/Constants.sol";

/**
 * @custom:feature The initiate close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 * @custom:and a validated long position of 1 ether with 10x leverage.
 */
contract TestUsdnProtocolActionsValidateClosePosition is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 private positionAmount = 1 ether;
    int24 private tick;
    uint256 private tickVersion;
    uint256 private index;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enablePositionFees = false;
        super._setUp(params);

        (tick, tickVersion, index) = setUpUserPositionInLong(
            address(this),
            ProtocolAction.ValidateOpenPosition,
            positionAmount,
            params.initialPrice - (params.initialPrice / 5),
            params.initialPrice
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user tries to validate a close position action with the wrong action pending
     * @custom:given An initiated open position
     * @custom:when The owner of the position calls _validateClosePosition
     * @custom:then The call reverts because the pending action is not ValidateClosePosition
     */
    function test_RevertsWhen_validateClosePositionWithTheWrongPendingAction() external {
        // Setup an initiate action to have a pending validate action for this user
        setUpUserPositionInLong(
            address(this),
            ProtocolAction.InitiateOpenPosition,
            positionAmount,
            params.initialPrice - (params.initialPrice / 5),
            params.initialPrice
        );

        bytes memory priceData = abi.encode(params.initialPrice);

        // Try to validate a close position action with a pending action other than ValidateClosePosition
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidPendingAction.selector));
        protocol.i_validateClosePosition(address(this), priceData);
    }

    /* -------------------------------------------------------------------------- */
    /*                            validateClosePosition                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A user validate closes a position but sends too much ether
     * @custom:given A validated long position
     * @custom:and oracle validation cost == 0
     * @custom:when User calls validateClosePosition with an amount of ether greater than the validation cost
     * @custom:then The protocol refunds the amount sent
     */
    function test_validateClosePositionRefundExcessEther() external {
        bytes memory priceData = abi.encode(params.initialPrice);
        uint256 etherBalanceBefore = address(this).balance;

        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        protocol.validateClosePosition{ value: 1 ether }(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            etherBalanceBefore,
            address(this).balance,
            "The sent ether should have been refunded as none of it was spent"
        );
    }

    /**
     * @custom:scenario A user validate closes a position with a pending action
     * @custom:given A validated long position
     * @custom:and an initiated open position action from another user
     * @custom:when User calls validateClosePosition with valid price data for the pending action
     * @custom:then The user validates the pending action
     */
    function test_validateClosePositionValidatePendingAction() external {
        bytes memory priceData = abi.encode(params.initialPrice);
        // Initiate an open position action for another user
        setUpUserPositionInLong(
            USER_1,
            ProtocolAction.InitiateOpenPosition,
            positionAmount,
            params.initialPrice - (params.initialPrice / 5),
            params.initialPrice
        );

        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, EMPTY_PREVIOUS_DATA);

        skip(protocol.getValidationDeadline());

        bytes[] memory previousData = new bytes[](1);
        previousData[0] = priceData;
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 1;

        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(USER_1, 0, 0, 0, 0, 0);
        protocol.validateClosePosition(priceData, PreviousActionsData(previousData, rawIndices));
    }

    /**
     * @custom:scenario A user validate closes a position
     * @custom:given A validated long position
     * @custom:when User calls validateClosePosition
     * @custom:then The user validate his initiated close position action
     */
    function test_validateClosePosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);
        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        vm.expectEmit(true, false, false, false);
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, positionAmount, -1);
        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);
    }

    /* -------------------------------------------------------------------------- */
    /*                           _validateClosePosition                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user validates a close position action
     * @custom:given A validated open position of 1 wsteth
     * @custom:when The user validate the close of the position
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receives half of the position amount
     */
    function test_internalValidateClosePosition() external {
        uint128 price = params.initialPrice;
        bytes memory priceData = abi.encode(price);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos, uint8 liquidationPenalty) = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));
        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 totalExpoToClose = FixedPointMathLib.fullMulDiv(pos.totalExpo, positionAmount, pos.amount).toUint128();
        uint256 liqMultiplier = protocol.getLiquidationMultiplier();
        (uint256 expectedAmountReceived,) = protocol.i_assetToTransfer(
            price, tick, liquidationPenalty, totalExpoToClose, liqMultiplier, action.closeTempTransfer
        );

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, expectedAmountReceived, -1);
        protocol.i_validateClosePosition(address(this), priceData);

        /* ----------------------------- User's Balance ----------------------------- */
        assertApproxEqAbs(
            assetBalanceBefore + positionAmount,
            wstETH.balanceOf(address(this)),
            1,
            "User should have received the amount to close approximately"
        );
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
    function test_internalValidatePartialClosePosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos,) = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));
        uint128 amountToClose = 100_000;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        (Position memory posBefore, uint8 liquidationPenalty) = protocol.getLongPosition(tick, tickVersion, index);
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 totalExpoToClose = FixedPointMathLib.fullMulDiv(pos.totalExpo, amountToClose, pos.amount).toUint128();
        (uint256 expectedAmountReceived,) = protocol.i_assetToTransfer(
            params.initialPrice,
            tick,
            liquidationPenalty,
            totalExpoToClose,
            protocol.getLiquidationMultiplier(),
            action.closeTempTransfer
        );

        // Sanity Check
        // If user is address(0), the position was deleted from the tick array
        assertEq(posBefore.user, address(this), "The position should not have been deleted");

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, expectedAmountReceived, -1);
        protocol.i_validateClosePosition(address(this), priceData);

        /* ---------------------------- Position's state ---------------------------- */
        (Position memory posAfter,) = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(posBefore.user, posAfter.user, "The user of the position should not have changed");
        assertEq(posBefore.timestamp, posAfter.timestamp, "Timestamp of the position should have stayed the same");
        assertEq(posBefore.totalExpo, posAfter.totalExpo, "The total expo should not have changed after the validation");
        assertEq(posBefore.amount, posAfter.amount, "The amount should not have changed after the validation");

        /* ----------------------------- User's Balance ----------------------------- */
        assertApproxEqAbs(
            assetBalanceBefore + amountToClose,
            wstETH.balanceOf(address(this)),
            1,
            "User should have received approximately the amount to close"
        );

        /* --------------------- Close the rest of the position --------------------- */
        protocol.initiateClosePosition(
            tick, tickVersion, index, pos.amount - amountToClose, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        (expectedAmountReceived,) = protocol.i_assetToTransfer(
            params.initialPrice,
            tick,
            protocol.getLiquidationPenalty(),
            pos.totalExpo - totalExpoToClose,
            protocol.getLiquidationMultiplier(),
            action.closeTempTransfer
        );

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, expectedAmountReceived, -1);
        protocol.i_validateClosePosition(address(this), priceData);

        (posAfter,) = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(posAfter.user, address(0), "The address should be 0x0 (position deleted)");
        assertEq(posAfter.amount, 0, "The amount should be 0");
        assertApproxEqAbs(
            assetBalanceBefore + pos.amount,
            wstETH.balanceOf(address(this)),
            2,
            "User should have received approximately his full amount back"
        );
    }

    /**
     * @custom:scenario Validate a partial close of a position that is losing money
     * @custom:given A validated open position
     * @custom:and The initiate position is already done for half of the position
     * @custom:and The price dipped below the entry price before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receive parts of his funds back
     */
    function test_internalValidatePartialCloseUnderwaterPosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos, uint8 liquidationPenalty) = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        uint128 amountToClose = pos.amount / 2;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 timestamp = uint128(block.timestamp);
        uint128 priceAfterInit = params.initialPrice - 50 ether;
        uint256 vaultBalanceBefore = uint256(protocol.vaultAssetAvailableWithFunding(priceAfterInit, timestamp));
        uint256 longBalanceBefore = uint256(protocol.longAssetAvailableWithFunding(priceAfterInit, timestamp));
        (uint256 assetToTransfer,) = protocol.i_assetToTransfer(
            priceAfterInit,
            action.tick,
            liquidationPenalty,
            action.closeTotalExpo,
            action.closeLiqMultiplier,
            action.closeTempTransfer
        );
        priceData = abi.encode(priceAfterInit);
        int256 losses = int256(assetToTransfer) - int256(uint256(action.closeAmount));

        assertLt(losses, 0, "User should have lost money on his position");

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, assetToTransfer, losses);
        protocol.i_validateClosePosition(address(this), priceData);

        assertEq(
            protocol.getAsset().balanceOf(address(this)),
            // Losses is a negative value
            assetBalanceBefore + uint256(int128(action.closeAmount) + losses),
            "User should have received his assets minus his losses"
        );

        /* -------------------------- Balance Vault & Long -------------------------- */
        assertEq(vaultBalanceBefore, protocol.getBalanceVault(), "Balance of the vault should not have changed");
        assertApproxEqAbs(
            uint256(int256(longBalanceBefore) - losses),
            protocol.getBalanceLong(),
            1,
            "Profits should have been subtracted from the long's balance"
        );
    }

    /**
     * @custom:scenario Validate a partial close of a position that just went in profit
     * @custom:given A validated open position
     * @custom:and The initiate position is already done for half of the position
     * @custom:and The price increased above by 200$ before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receives his funds back + some profits
     */
    function test_internalValidatePartialClosePositionInProfit() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos, uint8 liquidationPenalty) = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        uint128 amountToClose = pos.amount / 2;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 price = params.initialPrice + 200 ether;
        uint256 vaultBalanceBefore = uint256(protocol.vaultAssetAvailableWithFunding(price, uint128(block.timestamp)));
        uint256 longBalanceBefore = uint256(protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp)));
        (uint256 assetToTransfer,) = protocol.i_assetToTransfer(
            price,
            action.tick,
            liquidationPenalty,
            action.closeTotalExpo,
            action.closeLiqMultiplier,
            action.closeTempTransfer
        );
        priceData = abi.encode(price);
        int256 profits = int256(assetToTransfer - action.closeAmount);

        assertGt(profits, 0, "User should be in profits");

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, assetToTransfer, profits);
        protocol.i_validateClosePosition(address(this), priceData);

        assertEq(
            protocol.getAsset().balanceOf(address(this)),
            assetBalanceBefore + action.closeAmount + uint256(profits),
            "User should have received his assets + profits"
        );

        /* -------------------------- Balance Vault & Long -------------------------- */
        assertEq(vaultBalanceBefore, protocol.getBalanceVault(), "Balance of the vault should not have changed");
        assertApproxEqAbs(
            longBalanceBefore - uint256(profits),
            protocol.getBalanceLong(),
            1,
            "Profits should have been subtracted from the long's balance"
        );
    }

    /**
     * @custom:scenario Validate a partial close of a position that should be liquidated
     * @custom:given A validated open position
     * @custom:and The initiate position is already done for half of the position
     * @custom:and The price dipped below its liquidation price before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a LiquidatedPosition event is emitted
     * @custom:and the user doesn't receive his funds back
     */
    function test_internalValidatePartialCloseLiquidatePosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        (Position memory pos, uint8 liquidationPenalty) = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        uint128 amountToClose = pos.amount / 2;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 liquidationPrice = protocol.getEffectivePriceForTick(tick, action.closeLiqMultiplier);
        uint256 vaultBalanceBefore =
            uint256(protocol.vaultAssetAvailableWithFunding(liquidationPrice, uint128(block.timestamp)));
        uint256 longBalanceBefore =
            uint256(protocol.longAssetAvailableWithFunding(liquidationPrice, uint128(block.timestamp)));
        (uint256 assetToTransfer, int256 positionValue) = protocol.i_assetToTransfer(
            liquidationPrice,
            action.tick,
            liquidationPenalty,
            action.closeTotalExpo,
            action.closeLiqMultiplier,
            action.closeTempTransfer
        );
        assertGt(positionValue, 0, "position value should be positive");
        assertEq(assetToTransfer, uint256(positionValue), "asset to transfer vs position value");
        uint256 totalPositionsBefore = protocol.getTotalLongPositions();
        priceData = abi.encode(liquidationPrice);

        // Make sure we liquidate the tick and the position at once
        vm.expectEmit(true, true, false, false);
        emit LiquidatedTick(tick, tickVersion, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit LiquidatedPosition(address(this), 0, 0, 0, 0, 0);
        protocol.i_validateClosePosition(address(this), priceData);

        assertEq(
            protocol.getAsset().balanceOf(address(this)), assetBalanceBefore, "User should not have received any asset"
        );

        /* -------------------------- Balance Vault & Long -------------------------- */
        assertEq(
            vaultBalanceBefore + uint256(positionValue) + assetToTransfer,
            protocol.getBalanceVault(),
            "Collateral of the position should have been transferred to the vault"
        );
        assertEq(
            longBalanceBefore - uint256(positionValue) + action.closeTempTransfer - assetToTransfer,
            protocol.getBalanceLong(),
            "Collateral of the position should have been removed from the long side"
        );
        assertEq(protocol.getTotalLongPositions(), totalPositionsBefore - 1, "The position should have been removed");
    }

    /**
     * @custom:scenario Validate a close of a position that should be liquidated with bad debt
     * @custom:given A validated open position
     * @custom:and The initiate position is already done for the entirety of the deployer's position
     * @custom:and The price dipped below its liquidation price before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a LiquidatedPosition event is emitted
     * @custom:and the vault balance falls to zero
     */
    function test_internalValidateCloseLiquidatePositionZeroVaultBalance() public {
        // liquidate the position in setup, leaving only the deployer position
        uint256 liquidated = protocol.liquidate(abi.encode(7 * params.initialPrice / 10), 10);
        assertEq(liquidated, 1, "liquidated");

        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        tick = protocol.getEffectiveTickForPrice(params.initialPrice / 2)
            + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        (Position memory pos, uint8 liquidationPenalty) = protocol.getLongPosition(tick, 0, 0);
        vm.prank(DEPLOYER);
        protocol.initiateClosePosition(tick, 0, 0, pos.amount, priceData, EMPTY_PREVIOUS_DATA);

        /* ------------------ Validate close position with bad debt ----------------- */

        priceData = abi.encode(50 ether);
        skip(1 hours);

        (, int256 positionValue) = protocol.i_assetToTransfer(
            50 ether,
            tick,
            liquidationPenalty,
            pos.totalExpo,
            protocol.getLiquidationMultiplier(uint128(block.timestamp)),
            0
        );
        assertLt(positionValue, 0, "position value should be negative");

        // Make sure we liquidate the position
        vm.expectEmit(true, false, false, false);
        emit LiquidatedPosition(DEPLOYER, 0, 0, 0, 0, 0);
        protocol.i_validateClosePosition(DEPLOYER, priceData);

        assertEq(protocol.getBalanceVault(), 0, "final vault balance");
    }

    /**
     * @custom:scenario Validate a close of a position that should be liquidated and end up with zero long balance
     * @custom:given A validated open position
     * @custom:and The initiate position is already done for the entirety of the deployer's position, right at the
     * liquidation price
     * @custom:and The price dipped just below its liquidation price before the validation
     * @custom:when The owner of the position validates the close position action
     * @custom:then The state of the protocol is updated
     * @custom:and a LiquidatedPosition event is emitted
     * @custom:and the long balance falls to zero
     */
    function test_internalValidateCloseLiquidatePositionZeroLongBalance() public {
        // liquidate the position in setup, leaving only the deployer position
        uint256 liquidated = protocol.liquidate(abi.encode(7 * params.initialPrice / 10), 10);
        assertEq(liquidated, 1, "liquidated");

        // we initiate the close with a price that leaves little remaining collateral
        tick = protocol.getEffectiveTickForPrice(params.initialPrice / 2)
            + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        uint128 liquidationPrice = protocol.getEffectivePriceForTick(tick);
        bytes memory priceData = abi.encode(liquidationPrice);

        /* ------------------------- Initiate Close Position ------------------------ */

        (Position memory pos, uint8 liquidationPenalty) = protocol.getLongPosition(tick, 0, 0);
        vm.prank(DEPLOYER);
        protocol.initiateClosePosition(tick, 0, 0, pos.amount, priceData, EMPTY_PREVIOUS_DATA);

        /* ---- Validate close position with a large enough remaining collateral ---- */

        _waitDelay();
        priceData = abi.encode(liquidationPrice - 1);

        (, int256 positionValue) = protocol.i_assetToTransfer(
            liquidationPrice - 1,
            tick,
            liquidationPenalty,
            pos.totalExpo,
            protocol.getLiquidationMultiplier(uint128(block.timestamp)),
            0
        );
        assertGt(positionValue, 0, "position value should be positive");

        // Make sure we liquidate the position
        vm.expectEmit(true, false, false, false);
        emit LiquidatedPosition(DEPLOYER, 0, 0, 0, 0, 0);
        protocol.i_validateClosePosition(DEPLOYER, priceData);

        assertEq(protocol.getBalanceLong(), 0, "final long balance");
    }

    /// @dev Allow refund tests
    receive() external payable { }
}
