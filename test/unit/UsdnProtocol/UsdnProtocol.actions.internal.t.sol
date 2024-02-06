// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test internal functions of the actions layer
 */
contract TestUsdnProtocolActionsInternal is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check value of the `assetToTransfer` function
     * @custom:given The position value is lower than the long available balance
     * @custom:and The position of amount 1 wstETH has a starting price slightly below $500 with leverage 2x
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
     * @custom:and The position of amount 100 wstETH has a starting price slightly below $500 with leverage 2x
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
}
