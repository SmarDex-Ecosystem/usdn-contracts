// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @custom:feature Test the _assetToTransfer internal function of the actions layer
 */
contract TestUsdnProtocolActionsAssetToTransfer is UsdnProtocolBaseFixture {
    using Strings for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
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
        int24 tick = protocol.getEffectiveTickForPrice(DEFAULT_PARAMS.initialPrice / 4);
        uint256 res = protocol.i_assetToTransfer(
            tick, 1 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()), protocol.liquidationMultiplier()
        );
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
        int24 tick = protocol.getEffectiveTickForPrice(DEFAULT_PARAMS.initialPrice / 4);
        uint256 longAvailable = uint256(protocol.longAssetAvailable(DEFAULT_PARAMS.initialPrice)); // 5 ether
        uint256 res = protocol.i_assetToTransfer(
            tick, 100 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()), protocol.liquidationMultiplier()
        );
        assertEq(res, longAvailable);
    }

    /**
     * @custom:scenario Check value of the `assetToTransfer` function when the long balance is zero
     * @custom:given The long balance is empty
     * @custom:when the asset to transfer is calculated
     * @custom:then The asset to transfer is zero
     */
    function test_assetToTransferZeroBalance() public {
        // TODO : fix this test with #102
        vm.skip(true);
        int24 firstPosTick = protocol.getEffectiveTickForPrice(DEFAULT_PARAMS.initialPrice / 2);
        skip(60); // we need that the oracle timestamp be newer than the last price update
        // liquidate the default position
        uint128 liqPrice = protocol.getEffectivePriceForTick(firstPosTick);
        protocol.liquidate(abi.encode(liqPrice), 10);

        assertEq(protocol.totalLongPositions(), 0, "total long positions");
        assertEq(protocol.i_longTradingExpo(liqPrice), 0, "long trading expo with funding");
        assertEq(protocol.balanceLong(), 0, "balance long");
        assertEq(protocol.longAssetAvailable(liqPrice), 0, "long asset available");

        int24 tick = protocol.getEffectiveTickForPrice(liqPrice);
        uint256 res = protocol.i_assetToTransfer(
            tick, 100 ether, uint128(10 ** protocol.LEVERAGE_DECIMALS()), protocol.liquidationMultiplier()
        );
        assertEq(res, 0, "asset to transfer");
    }
}
