// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { LongPendingAction, Position, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The initiate close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 100_000 wstETH in their wallet
 */
contract TestUsdnProtocolActionsValidateClosePosition is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 private positionAmount = 1 ether;
    int24 private tick;
    uint256 private tickVersion;
    uint256 private index;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.enableFunding = false;
        params.enablePositionFees = false;
        params.enableProtocolFees = false;

        super._setUp(params);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 100_000 ether, address(protocol), type(uint256).max);

        (tick, tickVersion, index) = setUpUserPositionInLong(
            address(this),
            ProtocolAction.ValidateOpenPosition,
            positionAmount,
            params.initialPrice - 200 ether,
            params.initialPrice
        );
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

        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, "");
        _waitDelay();
        protocol.validateClosePosition{ value: 1 ether }(priceData, "");

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
     * @custom:and oracle validation cost == 0
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
            params.initialPrice - 200 ether,
            params.initialPrice
        );

        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, "");

        skip(protocol.getValidationDeadline());

        vm.expectEmit(true, false, false, false);
        emit ValidatedOpenPosition(USER_1, 0, 0, 0, 0, 0);
        protocol.validateClosePosition(priceData, priceData);
    }

    /**
     * @custom:scenario A user validate closes a position
     * @custom:given A validated long position
     * @custom:when User calls validateClosePosition
     * @custom:then The user validate his iniitiated close position action
     */
    function test_validateClosePosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);
        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, "");
        _waitDelay();

        vm.expectEmit(true, true, true, false);
        emit ValidatedClosePosition(address(this), tick, tickVersion, 0, 0, 0);
        protocol.validateClosePosition(priceData, "");
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
    function test__validateClosePosition() public {
        uint128 price = params.initialPrice;
        bytes memory priceData = abi.encode(price);

        /* ------------------------- Initiate Close Position ------------------------ */
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));
        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount, priceData, "");
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 totalExpoToClose = FixedPointMathLib.fullMulDiv(pos.totalExpo, positionAmount, pos.amount).toUint128();
        uint256 liqMultiplier = protocol.getLiquidationMultiplier();
        uint256 expectedAmountReceived =
            protocol.i_assetToTransfer(price, tick, totalExpoToClose, liqMultiplier, action.closeTempTransfer);

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
    function test__validatePartialClosePosition() external {
        uint128 price = params.initialPrice;
        bytes memory priceData = abi.encode(price);

        /* ------------------------- Initiate Close Position ------------------------ */
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));
        uint128 amountToClose = 100_000;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        Position memory posBefore = protocol.getLongPosition(tick, tickVersion, index);
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 totalExpoToClose = FixedPointMathLib.fullMulDiv(pos.totalExpo, amountToClose, pos.amount).toUint128();
        uint256 liqMultiplier = protocol.getLiquidationMultiplier();
        uint256 expectedAmountReceived =
            protocol.i_assetToTransfer(price, tick, totalExpoToClose, liqMultiplier, action.closeTempTransfer);

        // Sanity Check
        // If user is address(0), the position was deleted from the tick array
        assertEq(posBefore.user, address(this), "The position should not have been deleted");

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, expectedAmountReceived, -1);
        protocol.i_validateClosePosition(address(this), priceData);

        /* ---------------------------- Position's state ---------------------------- */
        Position memory posAfter = protocol.getLongPosition(tick, tickVersion, index);
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
        protocol.initiateClosePosition(tick, tickVersion, index, pos.amount - amountToClose, priceData, "");
        _waitDelay();
        action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        expectedAmountReceived = protocol.i_assetToTransfer(
            price, tick, pos.totalExpo - totalExpoToClose, liqMultiplier, action.closeTempTransfer
        );

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, expectedAmountReceived, -1);
        protocol.i_validateClosePosition(address(this), priceData);

        posAfter = protocol.getLongPosition(tick, tickVersion, index);
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
    function test__validatePartialCloseUnderwaterPosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        uint128 amountToClose = pos.amount / 2;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 timestamp = uint128(block.timestamp);
        uint128 priceAfterInit = params.initialPrice - 50 ether;
        uint256 vaultBalanceBefore = uint256(protocol.vaultAssetAvailableWithFunding(priceAfterInit, timestamp));
        uint256 longBalanceBefore = uint256(protocol.longAssetAvailableWithFunding(priceAfterInit, timestamp));
        uint256 assetToTransfer = protocol.i_assetToTransfer(
            priceAfterInit, action.tick, action.closeTotalExpo, action.closeLiqMultiplier, action.closeTempTransfer
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
    function test__validatePartialClosePositionInProfit() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        uint128 amountToClose = pos.amount / 2;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");
        _waitDelay();

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 price = params.initialPrice + 200 ether;
        uint256 vaultBalanceBefore = uint256(protocol.vaultAssetAvailableWithFunding(price, uint128(block.timestamp)));
        uint256 longBalanceBefore = uint256(protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp)));
        uint256 assetToTransfer = protocol.i_assetToTransfer(
            price, action.tick, action.closeTotalExpo, action.closeLiqMultiplier, action.closeTempTransfer
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
    function test__validatePartialCloseLiquidatePosition() external {
        bytes memory priceData = abi.encode(params.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        uint128 amountToClose = pos.amount / 2;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");
        _waitDelay();

        Position memory remainingPos = protocol.getLongPosition(tick, tickVersion, index);

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 liquidationPrice = protocol.getEffectivePriceForTick(tick, action.closeLiqMultiplier);
        uint256 vaultBalanceBefore =
            uint256(protocol.vaultAssetAvailableWithFunding(liquidationPrice, uint128(block.timestamp)));
        uint256 longBalanceBefore =
            uint256(protocol.longAssetAvailableWithFunding(liquidationPrice, uint128(block.timestamp)));
        uint256 remainingPosTickValue = uint256(protocol.i_tickValue(liquidationPrice, tick, remainingPos.totalExpo));
        uint256 assetToTransfer = protocol.i_assetToTransfer(
            liquidationPrice, action.tick, action.closeTotalExpo, action.closeLiqMultiplier, action.closeTempTransfer
        );
        uint256 longPositionsAmountBefore = protocol.getTotalLongPositions();
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
            vaultBalanceBefore + remainingPosTickValue + assetToTransfer,
            protocol.getBalanceVault(),
            "Collateral of the position should have been transferred to the vault"
        );
        assertEq(
            longBalanceBefore - remainingPosTickValue + action.closeTempTransfer - assetToTransfer,
            protocol.getBalanceLong(),
            "Collateral of the position should have been removed from the long side"
        );
        assertEq(
            protocol.getTotalLongPositions(), longPositionsAmountBefore - 1, "The position should have been removed"
        );
    }

    /// @dev Allow refund tests
    receive() external payable { }
}
