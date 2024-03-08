// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import {
    ProtocolAction,
    LongPendingAction,
    PendingAction,
    Position
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature The close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 100_000 wstETH in their wallet
 * @custom:and A position with 500 wstETH in collateral
 */
contract TestUsdnProtocolActionsClosePosition is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint96 private positionAmount = 1 ether;
    int24 private tick;
    uint256 private tickVersion;
    uint256 private index;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);

        vm.prank(ADMIN);
        protocol.setFundingSF(0);
        protocol.setEMA(0);

        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);

        (tick, tickVersion, index) =
            protocol.initiateOpenPosition(positionAmount, params.initialPrice - 200 ether, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);

        // Add more to balance long because of a bug in _positionValue calculation
        protocol.initiateOpenPosition(10 ether, params.initialPrice - 1000 ether, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
    }

    /**
     * @custom:scenario A user tries to close a position with an amount higher than the position's amount
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with an amount too high
     * @custom:then The call reverts
     */
    function test_RevertWhen_closePartialPositionWithAmountHigherThanPositionAmount() external {
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint128 amountToClose = pos.amount + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolAmountToCloseHigherThanPositionAmount.selector, pos.amount, amountToClose
            )
        );
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");
    }

    /**
     * @custom:scenario A user tries to close a position with 0 as the amount to close
     * @custom:given A validated open position
     * @custom:when The owner of the position calls initiateClosePosition with 0 as the amount to close
     * @custom:then The call reverts
     */
    function test_RevertWhen_closePartialPositionWithZeroAmount() external {
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolAmountToCloseIsZero.selector));
        protocol.initiateClosePosition(tick, tickVersion, index, 0, priceData, "");
    }

    /**
     * @custom:scenario A user tries to close a position that was previously liquidated
     * @custom:given A validated open position gets liquidated
     * @custom:when The owner of the position calls initiateClosePosition with half of the amount
     * @custom:then The call reverts because the position is not valid anymore
     */
    function test_RevertWhen_closePartialPositionWithAnOutdatedTick() external {
        bytes memory priceData = abi.encode(protocol.getEffectivePriceForTick(tick));

        // Liquidate the position
        protocol.liquidate(priceData, 1);
        (, uint256 version) = protocol.i_tickHash(tick);
        assertGt(version, tickVersion, "The tick should have been liquidated");

        // Try to close the position once the price comes back up
        priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolOutdatedTick.selector, tickVersion + 1, tickVersion));
        protocol.initiateClosePosition(tick, tickVersion, index, positionAmount / 2, priceData, "");
    }

    /**
     * @custom:scenario Initiate close a position partially
     * @custom:given A validated open position
     * @custom:when The owner of the position closes half of the position at the same price as the opening
     * @custom:then The state of the protocol is updated and an InitiatedClosePosition event is emitted
     */
    function test_initiatePartialClosePosition() external {
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        Position memory posBefore = protocol.getLongPosition(tick, tickVersion, index);
        uint128 amountToClose = positionAmount / 2;
        uint128 totalExpoToClose =
            FixedPointMathLib.fullMulDiv(posBefore.totalExpo, amountToClose, posBefore.amount).toUint128();
        uint256 totalExpoBefore = protocol.getTotalExpo();
        uint256 balanceLongBefore = protocol.getBalanceLong();

        /* ------------------------ Initiate the close action ----------------------- */
        vm.expectEmit();
        emit InitiatedClosePosition(address(this), tick, tickVersion, index, amountToClose, totalExpoToClose);
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");

        Position memory posAfter = protocol.getLongPosition(tick, tickVersion, index);
        // If user is address(0), the position was deleted from the tick array
        assertEq(posBefore.user, address(this), "The position should not have been deleted");

        /* ---------------------------- Position's state ---------------------------- */
        assertEq(posBefore.user, posAfter.user, "The user of the position should not have changed");
        assertEq(posBefore.timestamp, posAfter.timestamp, "Timestamp of the position should have stayed the same");
        assertEq(
            posBefore.totalExpo - totalExpoToClose,
            posAfter.totalExpo,
            "The total expo to close should have been subtracted from the original total expo of the position"
        );
        assertEq(
            posBefore.amount - amountToClose,
            posAfter.amount,
            "The amount to close should have been subtracted from the original amount of the position"
        );

        /* ------------------------- Pending action's state ------------------------- */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertEq(
            action.closeTotalExpo, totalExpoToClose, "Total expo of pending action should be equal to totalExpoToClose"
        );
        assertEq(action.closeAmount, amountToClose, "Amount of pending action should be equal to the amount to close");

        /* ----------------------------- Protocol State ----------------------------- */
        assertEq(
            totalExpoBefore - totalExpoToClose,
            protocol.getTotalExpo(),
            "totalExpoToClose should have been subtracted from the total expo of the protocol"
        );
        uint256 assetToTransfer = protocol.i_assetToTransfer(price, tick, totalExpoToClose, action.closeLiqMultiplier);
        assertEq(
            balanceLongBefore - assetToTransfer,
            protocol.getBalanceLong(),
            "assetToTransfer should have been subtracted from the long balance of the protocol"
        );
    }

    /**
     * @custom:scenario Validate a partial close of a position
     * @custom:given A validated open position
     * @custom:and the initiate position is already done for half of the position
     * @custom:when The owner of the position validates the position closing
     * @custom:then The state of the protocol is updated
     * @custom:and a ValidatedClosePosition event is emitted
     * @custom:and the user receives half of the position amount
     */
    function test_validatePartialClosePosition() external {
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        /* ------------------------- Initiate Close Position ------------------------ */
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));
        uint128 amountToClose = 100_000;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);

        /* ------------------------- Validate Close Position ------------------------ */
        uint128 totalExpoToClose = FixedPointMathLib.fullMulDiv(pos.totalExpo, amountToClose, pos.amount).toUint128();
        uint256 liqMultiplier = protocol.getLiquidationMultiplier();
        uint256 expectedAmountReceived = protocol.i_assetToTransfer(price, tick, totalExpoToClose, liqMultiplier);

        Position memory posBefore = protocol.getLongPosition(tick, tickVersion, index);
        // Sanity Check
        // If user is address(0), the position was deleted from the tick array
        assertEq(posBefore.user, address(this), "The position should not have been deleted");

        vm.expectEmit();
        emit ValidatedClosePosition(address(this), tick, tickVersion, index, expectedAmountReceived, -1);
        protocol.validateClosePosition(priceData, "");

        assertApproxEqAbs(
            protocol.getAsset().balanceOf(address(this)),
            assetBalanceBefore + amountToClose,
            1,
            "Test contract address should have received his collateral + his profits"
        );

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
            "User should have received the amount to close approximately"
        );

        protocol.initiateClosePosition(tick, tickVersion, index, pos.amount - amountToClose, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateClosePosition(priceData, "");
        posAfter = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(posAfter.amount, 0, "The amount should be 0");
        assertApproxEqAbs(
            assetBalanceBefore + pos.amount,
            wstETH.balanceOf(address(this)),
            2,
            "User should have received approximately his full amount back"
        );
    }

    /**
     * @custom:scenario Validate a partial close of a position that should be liquidated
     * @custom:given A validated open position
     * @custom:and The initiate position is already done for half of the position
     * @custom:and The price dipped below its liquidation price before the validation
     * @custom:when The owner of the position validates the position closing
     * @custom:then The state of the protocol is updated
     * @custom:and a LiquidatedPosition event is emitted
     * @custom:and the user doesn't receive his funds back
     */
    function test_validatePartialClosePositionUnderwater() external {
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);

        /* ------------------------- Initiate Close Position ------------------------ */
        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        uint256 assetBalanceBefore = protocol.getAsset().balanceOf(address(this));

        uint128 amountToClose = pos.amount / 2;
        protocol.initiateClosePosition(tick, tickVersion, index, amountToClose, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);

        Position memory remainingPos = protocol.getLongPosition(tick, tickVersion, index);

        /* ------------------------- Validate Close Position ------------------------ */
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 liquidationPrice = protocol.getEffectivePriceForTick(tick, action.closeLiqMultiplier);
        uint256 vaultBalanceBefore =
            uint256(protocol.vaultAssetAvailableWithFunding(liquidationPrice, uint128(block.timestamp)));
        uint256 longBalanceBefore =
            uint256(protocol.longAssetAvailableWithFunding(liquidationPrice, uint128(block.timestamp)));
        uint256 remainingPosTickValue = uint256(protocol.i_tickValue(liquidationPrice, tick, remainingPos.totalExpo));
        uint256 assetToTransfer =
            protocol.i_assetToTransfer(liquidationPrice, action.tick, action.closeTotalExpo, action.closeLiqMultiplier);
        priceData = abi.encode(liquidationPrice);

        // Make sure we liquidate the tick and the position at once
        vm.expectEmit(true, true, false, false);
        emit LiquidatedTick(tick, tickVersion, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit LiquidatedPosition(address(this), 0, 0, 0, 0, 0);
        protocol.validateClosePosition(priceData, "");

        assertEq(
            protocol.getAsset().balanceOf(address(this)),
            assetBalanceBefore,
            "Test contract address should not have received any asset"
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
    }
}
