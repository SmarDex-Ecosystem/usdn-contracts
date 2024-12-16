// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature The `_flashClosePosition` internal function of the UsdnProtocolLong contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and A position created with 1 ether and a 2x leverage
 */
contract TestUsdnProtocolLongFlashClosePosition is UsdnProtocolBaseFixture {
    uint256 balanceVault;
    uint256 balanceLong;
    uint256 totalExpo;
    HugeUint.Uint512 liqMultiplierAccumulator;
    uint128 constant AMOUNT = 1 ether;
    PositionId posId;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: AMOUNT,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice * 8 / 10,
                price: DEFAULT_PARAMS.initialPrice
            })
        );
        balanceVault = protocol.getBalanceVault();
        balanceLong = protocol.getBalanceLong();
        totalExpo = protocol.getTotalExpo();
        liqMultiplierAccumulator = protocol.getLiqMultiplierAccumulator();
    }

    /**
     * @custom:scenario Flash closing a position
     * @custom:when _flashClosePosition is called
     * @custom:then The provided position is closed
     * @custom:and InitiatedClosePosition and ValidatedClosePosition events are emitted
     */
    function test_flashClosePosition() public {
        (Position memory pos,) = protocol.getLongPosition(posId);

        uint256 longPositionsCountBefore = protocol.getTotalLongPositions();
        // 10% price increase
        uint128 currentPrice = DEFAULT_PARAMS.initialPrice * 11 / 10;
        int256 longAssetAvailable = protocol.i_longAssetAvailable(currentPrice);
        int256 vaultAssetAvailable = protocol.i_vaultAssetAvailable(currentPrice);
        uint128 tickPrice = protocol.getEffectivePriceForTick(
            protocol.i_calcTickWithoutPenalty(posId.tick, protocol.getLiquidationPenalty()),
            currentPrice,
            totalExpo - uint256(longAssetAvailable),
            liqMultiplierAccumulator
        );
        int256 expectedPositionValue = protocol.i_positionValue(pos.totalExpo, currentPrice, tickPrice);

        vm.expectEmit();
        emit InitiatedClosePosition(address(this), address(this), address(this), posId, AMOUNT, AMOUNT, 0);
        vm.expectEmit();
        emit ValidatedClosePosition(
            address(this),
            address(this),
            posId,
            uint256(expectedPositionValue),
            int256(expectedPositionValue) - int128(AMOUNT)
        );
        int256 positionValue = protocol.i_flashClosePosition(
            posId,
            currentPrice,
            totalExpo,
            uint256(longAssetAvailable),
            uint256(vaultAssetAvailable),
            liqMultiplierAccumulator
        );

        assertEq(positionValue, expectedPositionValue, "The returned position value should be the expected one");

        (pos,) = protocol.getLongPosition(posId);
        Position memory deletedPos;
        assertEq(abi.encode(pos), abi.encode(deletedPos), "The position should have been deleted");

        assertEq(
            longPositionsCountBefore - 1, protocol.getTotalLongPositions(), "The long position should have been closed"
        );
    }

    /**
     * @custom:scenario Flash closing a position with an outdated tick
     * @custom:given the tick version of the position's tick has been incremented
     * @custom:when _flashClosePosition is called
     * @custom:then The returned value is 0 because the position was liquidated
     */
    function test_flashClosePositionWithAnOutdatedTick() public {
        // increment the tick version of the position
        protocol.setTickVersion(posId.tick, posId.tickVersion + 1);

        int256 positionValue = protocol.i_flashClosePosition(
            posId, DEFAULT_PARAMS.initialPrice, totalExpo, balanceLong, balanceVault, liqMultiplierAccumulator
        );

        assertEq(positionValue, 0, "The returned value should be 0");
    }

    /**
     * @custom:scenario Flash closing a position that should be liquidated
     * @custom:when _flashClosePosition is called with a price below the liquidation price of the position
     * @custom:then The returned value is less than 0
     */
    function test_flashClosePositionWithAPositionWithNegativeValue() public {
        uint128 lastPrice = DEFAULT_PARAMS.initialPrice * 7 / 10;
        int256 longAssetAvailable = protocol.i_longAssetAvailable(lastPrice);
        int256 vaultAssetAvailable = protocol.i_vaultAssetAvailable(lastPrice);
        if (longAssetAvailable < 0) {
            vaultAssetAvailable += longAssetAvailable;
            longAssetAvailable = 0;
        }

        int256 positionValue = protocol.i_flashClosePosition(
            posId,
            lastPrice,
            totalExpo,
            uint256(longAssetAvailable),
            uint256(vaultAssetAvailable),
            liqMultiplierAccumulator
        );

        assertLt(positionValue, 0, "The returned value should be less than 0");
    }

    /**
     * @custom:scenario Flash closing a position with a position value higher than the long balance
     * @custom:when _flashClosePosition is called with a price is below the liquidation price of the position
     * @custom:then The returned value is less than 0
     */
    function test_flashClosePositionWithPositionValueHigherThanLongBalance() public {
        balanceVault = protocol.getBalanceVault();
        liqMultiplierAccumulator = protocol.getLiqMultiplierAccumulator();

        (Position memory pos,) = protocol.getLongPosition(posId);

        // manipulate the cached values to have a position value higher than the long balance
        balanceLong = pos.amount;
        totalExpo = pos.totalExpo;

        // 10% price increase
        uint128 currentPrice = DEFAULT_PARAMS.initialPrice * 11 / 10;
        uint128 tickPrice = protocol.getEffectivePriceForTick(
            protocol.i_calcTickWithoutPenalty(posId.tick, protocol.getLiquidationPenalty()),
            currentPrice,
            totalExpo - uint256(balanceLong),
            liqMultiplierAccumulator
        );
        int256 expectedPositionValue = protocol.i_positionValue(pos.totalExpo, currentPrice, tickPrice);

        // sanity check
        assertLt(
            int256(balanceLong),
            expectedPositionValue,
            "The long balance should be lower than the position value for this test to work, adjust the values of balanceLong and totalExpo"
        );

        vm.expectEmit();
        emit InitiatedClosePosition(address(this), address(this), address(this), posId, AMOUNT, AMOUNT, 0);
        vm.expectEmit();
        emit ValidatedClosePosition(
            address(this), address(this), posId, uint256(balanceLong), int256(balanceLong - AMOUNT)
        );
        int256 positionValue = protocol.i_flashClosePosition(
            posId, currentPrice, totalExpo, uint256(balanceLong), uint256(balanceVault), liqMultiplierAccumulator
        );

        assertEq(positionValue, int256(balanceLong), "The returned position value should be the expected one");
    }
}
