// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the _assetToTransfer internal function of the actions layer
 * @custom:background Given a protocol initialized with slightly more trading expo in the vault side.
 */
contract TestUsdnProtocolActionsAssetToTransfer is UsdnProtocolBaseFixture {
    using Strings for uint256;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 5 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario Check value of the `assetToTransfer` function
     * @custom:given The position value is lower than the long available balance
     * @custom:and The position of amount 1 wstETH has a liquidation price slightly below $500 with leverage 2x
     * (starting price slightly below $1000)
     * @custom:and The current price is $2000
     * @custom:when the asset to transfer is calculated
     * @custom:then The asset to transfer is slightly above 1.5 wstETH
     */
    function test_assetToTransfer() public {
        int24 tick = protocol.getEffectiveTickForPrice(params.initialPrice / 4);
        uint256 res =
            protocol.i_assetToTransfer(params.initialPrice, tick, 2 ether, protocol.getLiquidationMultiplier());
        assertEq(res, 1.512304848730381401 ether);
    }

    /**
     * @custom:scenario Check value of the `assetToTransfer` function when the long balance is too small
     * @custom:given The position value is higher than the long available balance
     * @custom:and The position of amount 100 wstETH has a liquidation price slightly below $500 with leverage 2x
     * (starting price slightly below $1000)
     * @custom:and The current price is $2000
     * @custom:when the asset to transfer is calculated
     * @custom:then The asset to transfer is equal to the long available balance (because we don't have 150 wstETH)
     */
    function test_assetToTransferNotEnoughBalance() public {
        int24 tick = protocol.getEffectiveTickForPrice(params.initialPrice / 4);
        uint256 longAvailable = uint256(protocol.i_longAssetAvailable(params.initialPrice)); // 5 ether
        uint256 res =
            protocol.i_assetToTransfer(params.initialPrice, tick, 200 ether, protocol.getLiquidationMultiplier());
        assertEq(res, longAvailable);
    }

    /**
     * @custom:scenario Check value of the `assetToTransfer` function when the long balance is zero
     * @custom:given The long balance is empty due to funding and price change
     * @custom:when the asset to transfer is calculated
     * @custom:then The asset to transfer is zero
     */
    function test_assetToTransferZeroBalance() public {
        uint128 price = 1000 ether;
        skip(1 weeks);
        // liquidate the default position
        protocol.liquidate(abi.encode(price), 10);

        assertEq(protocol.getTotalLongPositions(), 0, "total long positions");
        assertEq(protocol.i_longTradingExpo(price), 0, "long trading expo with funding");
        assertEq(protocol.getBalanceLong(), 0, "balance long");
        assertEq(protocol.i_longAssetAvailable(price), 0, "long asset available");

        int24 tick = protocol.getEffectiveTickForPrice(price);
        uint256 res =
            protocol.i_assetToTransfer(params.initialPrice, tick, 100 ether, protocol.getLiquidationMultiplier());
        assertEq(res, 0, "asset to transfer");
    }
}
