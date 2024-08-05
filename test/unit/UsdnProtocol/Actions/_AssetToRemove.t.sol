// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the _assetToRemove internal function of the actions layer
 * @custom:background Given a protocol initialized with slightly more trading expo in the vault side.
 */
contract TestUsdnProtocolActionsAssetToRemove is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check value of the `_assetToRemove` function
     * @custom:given The position value is lower than the long available balance
     * @custom:and The position of amount 1 wstETH has a liquidation price slightly below $500 with leverage 2x
     * (starting price slightly below $1000)
     * @custom:and The current price is $2000
     * @custom:when the asset to transfer is calculated
     * @custom:then Asset to transfer and position value are equal
     * @custom:and The asset to transfer is slightly above 1.5 wstETH
     */
    function test_assetToRemove() public view {
        int24 tick = protocol.getEffectiveTickForPrice(params.initialPrice / 4);
        uint128 liqPrice = protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(tick));
        int256 value = protocol.i_positionValue(params.initialPrice, liqPrice, 2 ether);
        uint256 toRemove = protocol.i_assetToRemove(params.initialPrice, liqPrice, 2 ether);
        assertEq(toRemove, uint256(value), "to transfer vs pos value");
        assertEq(toRemove, 1.512304848730381401 ether, "to transfer");
    }

    /**
     * @custom:scenario Check value of the `_assetToRemove` function when the long balance is too small
     * @custom:given The position value is higher than the long available balance
     * @custom:and The position of amount 100 wstETH has a liquidation price slightly below $500 with leverage 2x
     * (starting price slightly below $1000)
     * @custom:and The current price is $2000
     * @custom:when the asset to transfer is calculated
     * @custom:then Position value is greater than asset to transfer
     * @custom:and The asset to transfer is equal to the long available balance (because we don't have 150 wstETH)
     */
    function test_assetToRemoveNotEnoughBalance() public view {
        int24 tick = protocol.getEffectiveTickForPrice(params.initialPrice / 4);
        uint256 longAvailable = uint256(protocol.i_longAssetAvailable(params.initialPrice)); // 5 ether
        uint128 liqPrice = protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(tick));
        int256 value = protocol.i_positionValue(params.initialPrice, liqPrice, 200 ether);
        uint256 toRemove = protocol.i_assetToRemove(params.initialPrice, liqPrice, 200 ether);
        assertGt(uint256(value), toRemove, "value vs asset to transfer");
        assertEq(toRemove, longAvailable, "asset to transfer vs long asset available");
    }

    /**
     * @custom:scenario Check value of the `_assetToRemove` function when the long balance is zero
     * @custom:given The long balance is empty due to funding and price change
     * @custom:when the asset to transfer is calculated
     * @custom:then The asset to transfer is zero
     */
    function test_assetToRemoveZeroBalance() public {
        uint128 price = 500 ether;
        skip(1 weeks);
        // liquidate the default position
        protocol.mockLiquidate(abi.encode(price), 10);

        assertEq(protocol.getTotalLongPositions(), 0, "total long positions");
        assertEq(protocol.getLongTradingExpo(price), 0, "long trading expo with funding");
        assertEq(protocol.getBalanceLong(), 0, "balance long");
        assertEq(protocol.i_longAssetAvailable(price), 0, "long asset available");

        int24 tick = protocol.getEffectiveTickForPrice(price);
        uint256 toRemove = protocol.i_assetToRemove(
            params.initialPrice, protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(tick)), 100 ether
        );
        assertEq(toRemove, 0, "asset to transfer");
    }
}
