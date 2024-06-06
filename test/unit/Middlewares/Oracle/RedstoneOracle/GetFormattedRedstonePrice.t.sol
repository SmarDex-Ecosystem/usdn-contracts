// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";
import {
    REDSTONE_ETH_PRICE, REDSTONE_ETH_DATA, REDSTONE_ETH_TIMESTAMP
} from "test/unit/Middlewares/utils/Constants.sol";

/**
 * @custom:feature The `getFormattedRedstonePrice` function of `RedstoneOracle`
 */
contract TestRedstoneOracleGetFormattedRedstonePrice is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function test_extractPriceUpdateTimestamp() public {
        assertEq(
            oracleMiddleware.i_getFormattedRedstonePrice(
                REDSTONE_ETH_TIMESTAMP, oracleMiddleware.getDecimals(), REDSTONE_ETH_DATA
            ).price,
            REDSTONE_ETH_PRICE,
            "block timestamp = calldata timestamp"
        );
        vm.warp(REDSTONE_ETH_TIMESTAMP + oracleMiddleware.getRedstoneRecentPriceDelay());
        assertEq(
            oracleMiddleware.i_getFormattedRedstonePrice(0, oracleMiddleware.getDecimals(), REDSTONE_ETH_DATA).timestamp,
            REDSTONE_ETH_TIMESTAMP,
            "block timestamp = calldata timestamp + delay"
        );
    }

    function test_RevertWhen_extractPriceUpdateTimestampRecentTooOld() public {
        vm.warp(REDSTONE_ETH_TIMESTAMP + oracleMiddleware.getRedstoneRecentPriceDelay() + 1);
        uint8 decimals = oracleMiddleware.getDecimals();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(0, decimals, REDSTONE_ETH_DATA);
    }

    function test_RevertWhen_extractPriceUpdateTimestampTooOld() public {
        uint8 decimals = oracleMiddleware.getDecimals();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(REDSTONE_ETH_TIMESTAMP + 1, decimals, REDSTONE_ETH_DATA);
    }

    function test_RevertWhen_extractPriceUpdateTimestampTooRecent() public {
        uint8 decimals = oracleMiddleware.getDecimals();
        uint48 heartbeat = oracleMiddleware.REDSTONE_HEARTBEAT();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooRecent.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(REDSTONE_ETH_TIMESTAMP - heartbeat, decimals, REDSTONE_ETH_DATA);
    }
}
