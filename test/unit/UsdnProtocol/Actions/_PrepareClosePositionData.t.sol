// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test of the protocol `_prepareClosePositionData` internal function
 * @custom:background Given a protocol with a long position that can be closed
 */
contract TestUsdnProtocolActionsPrepareClosePositionData is UsdnProtocolBaseFixture {
    uint128 private constant POSITION_AMOUNT = 0.1 ether;
    PositionId private posId;
    uint128 private liqPrice;
    bytes private currentPriceData;
    uint40 private timestampAtInitiate;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        timestampAtInitiate = uint40(block.timestamp);
        posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice * 2 / 3, // 3x leverage
                price: params.initialPrice
            })
        );

        currentPriceData = abi.encode(params.initialPrice);

        // skip to update the last price during the next call
        skip(30 minutes);

        liqPrice = protocol.getEffectivePriceForTick(posId.tick);
    }

    /**
     * @custom:scenario _prepareClosePositionData is called at the same price as the position's start price
     * @custom:given The price did not change between the open and the call
     * @custom:when _prepareClosePositionData is called
     * @custom:then The matching data is returned
     * @custom:and The position should not have been liquidated
     */
    function test_prepareClosePositionData() public {
        (ClosePositionData memory data, bool liquidated) = protocol.i_prepareClosePositionData(
            PrepareInitiateClosePositionParams(
                address(this), address(this), posId, POSITION_AMOUNT, 0, type(uint256).max, currentPriceData, "", ""
            )
        );

        assertFalse(liquidated, "The position should not have been liquidated");
        assertFalse(data.isLiquidationPending, "There should be no pending liquidation");
        _assertData(data, false);
    }

    /**
     * @custom:scenario _prepareClosePositionData is called with a price that would liquidate the position
     * @custom:given A current price below the position's liquidation price
     * @custom:when _prepareClosePositionData is called
     * @custom:then The matching data is returned
     * @custom:and The position should have been liquidated
     * @custom:and the function should have returned early
     */
    function test_prepareClosePositionDataWithALiquidatedPosition() public {
        currentPriceData = abi.encode(liqPrice);
        (ClosePositionData memory data, bool liquidated) = protocol.i_prepareClosePositionData(
            PrepareInitiateClosePositionParams(
                address(this), address(this), posId, POSITION_AMOUNT, 0, type(uint256).max, currentPriceData, "", ""
            )
        );

        assertTrue(liquidated, "The position should have been liquidated");
        assertFalse(data.isLiquidationPending, "There should be no pending liquidation");
        _assertData(data, true);
    }

    /**
     * @custom:scenario _prepareClosePositionData is called with 2 ticks that can be liquidated
     * @custom:given A current price below the position to close's liquidation price
     * @custom:and A high risk position that will be liquidated first
     * @custom:and A liquidation iterations setting at 1
     * @custom:when _prepareClosePositionData is called
     * @custom:then The matching data is returned
     * @custom:and The high risk position should have been liquidated
     * @custom:and The provided position was not liquidated
     * @custom:and The function should have returned early
     * @custom:and There should be pending liquidations
     */
    function test_prepareClosePositionDataWithPendingLiquidations() public {
        // open a long to liquidate
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice * 9 / 10, // 10x leverage
                price: params.initialPrice
            })
        );
        skip(30 minutes);

        vm.prank(ADMIN);
        protocol.setLiquidationIteration(1);

        currentPriceData = abi.encode(liqPrice);

        (ClosePositionData memory data, bool liquidated) = protocol.i_prepareClosePositionData(
            PrepareInitiateClosePositionParams(
                address(this), address(this), posId, POSITION_AMOUNT, 0, type(uint256).max, currentPriceData, "", ""
            )
        );

        assertFalse(liquidated, "The position should have been liquidated");
        assertTrue(data.isLiquidationPending, "There should be pending liquidations");
        _assertData(data, true);
    }

    /// @notice Assert the data in ClosePositionData depending on `isEarlyReturn`
    function _assertData(ClosePositionData memory data, bool isEarlyReturn) private view {
        uint128 currentPrice = abi.decode(currentPriceData, (uint128));
        uint24 liquidationPenalty = protocol.getLiquidationPenalty();
        uint256 positionTotalExpo = protocol.i_calcPositionTotalExpo(
            POSITION_AMOUNT,
            params.initialPrice,
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick))
        );

        // asserts that should be done independently from the `isEarlyReturn` param
        assertTrue(data.pos.validated, "The corresponding position should be validated");
        assertEq(
            data.pos.timestamp,
            timestampAtInitiate,
            "The timestamp should be equal to the timestamp of the initiate action"
        );
        assertEq(
            data.pos.totalExpo, positionTotalExpo, "The total expo of the position should match the expected value"
        );
        assertEq(data.pos.amount, POSITION_AMOUNT, "The amount of the position should match the expected value");
        assertEq(data.liquidationPenalty, liquidationPenalty, "The liquidation penalty should match the expected value");

        if (isEarlyReturn) {
            assertEq(data.totalExpoToClose, 0, "The total expo to close should not be set");
            assertEq(data.tempPositionValue, 0, "The position value should not be set");
            assertEq(data.longTradingExpo, 0, "The long trading expo should not be set");
            assertEq(data.liqMulAcc.lo, 0, "The liq multiplier accumulator should not be set");
        } else {
            assertEq(
                data.totalExpoToClose,
                positionTotalExpo,
                "The total expo to close should equal the total expo of the position"
            );
            assertEq(data.lastPrice, currentPrice, "The last price should match the expected value");
            assertEq(
                data.tempPositionValue,
                uint256(protocol.getPositionValue(posId, currentPrice, uint40(block.timestamp))),
                "The position value should match the expected value"
            );
            assertEq(
                data.longTradingExpo,
                protocol.getLongTradingExpo(currentPrice),
                "The long trading expo should match the expected value"
            );
            assertEq(
                data.liqMulAcc.lo,
                protocol.getLiqMultiplierAccumulator().lo,
                "The liq multiplier accumulator should match the expected value"
            );
        }
    }
}
