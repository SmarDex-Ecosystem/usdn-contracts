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

    /**
     * @custom:scenario Check that `getFormattedRedstonePrice` function returns the correct price
     * @custom:given The calldata with a known price, timestamp and signature
     * @custom:when The `getFormattedRedstonePrice` function is called with a timestamp set to 0
     * @custom:and The `getFormattedRedstonePrice` function is called with a timestamp in a 10-seconds window starting
     * at the target timestamp
     * @custom:then It should succeed
     */
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

    /**
     * @custom:scenario Check that `getFormattedRedstonePrice` function reverts when the price update timestamp is older
     * than block timestamp + price delay
     * @custom:given The calldata with a known timestamp and signature
     * @custom:when The `getFormattedRedstonePrice` function is called with a timestamp too old of 1 second
     * (targetTimestamp = 0)
     * @custom:then It should revert
     */
    function test_RevertWhen_extractPriceUpdateTimestampRecentTooOld() public {
        vm.warp(REDSTONE_ETH_TIMESTAMP + oracleMiddleware.getRedstoneRecentPriceDelay() + 1);
        uint8 decimals = oracleMiddleware.getDecimals();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(0, decimals, REDSTONE_ETH_DATA);
    }

    /**
     * @custom:scenario Check that `getFormattedRedstonePrice` function reverts when the price update timestamp is older
     * than specified target timestamp
     * @custom:given The calldata with a known timestamp and signature
     * @custom:when The `getFormattedRedstonePrice` function is called with a timestamp too old of 1 second
     * (targetTimestamp = calldata timestamp + 1)
     * @custom:then It should revert
     */
    function test_RevertWhen_extractPriceUpdateTimestampTooOld() public {
        uint8 decimals = oracleMiddleware.getDecimals();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(REDSTONE_ETH_TIMESTAMP + 1, decimals, REDSTONE_ETH_DATA);
    }

    /**
     * @dev Target timestamp + heartbeat represents the external (second) into the interval representing the allowed
     * price extraction window. It is therefore too recent because it representing the maximum + 1 second timestamp that
     * can be accepted
     * @custom:scenario Check that `getFormattedRedstonePrice` function reverts when the price update timestamp is too
     * recent (too much after the target timestamp)
     * @custom:given The calldata with a known timestamp and signature
     * @custom:when The `getFormattedRedstonePrice` function is called with a timestamp too recent of 1 second
     * (targetTimestamp = calldata timestamp - heartbeat)
     * @custom:then It should revert
     */
    function test_RevertWhen_extractPriceUpdateTimestampTooRecent() public {
        uint8 decimals = oracleMiddleware.getDecimals();
        uint48 heartbeat = oracleMiddleware.REDSTONE_HEARTBEAT();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooRecent.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(REDSTONE_ETH_TIMESTAMP - heartbeat, decimals, REDSTONE_ETH_DATA);
    }
}
