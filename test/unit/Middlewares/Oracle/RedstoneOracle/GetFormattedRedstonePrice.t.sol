// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { REDSTONE_ETH_DATA, REDSTONE_ETH_PRICE, REDSTONE_ETH_TIMESTAMP } from "../../utils/Constants.sol";
import { OracleMiddlewareWithRedstoneFixture } from "../../utils/Fixtures.sol";

import { RedstonePriceInfo } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/// @custom:feature The `getFormattedRedstonePrice` function of `RedstoneOracle`
contract TestRedstoneOracleGetFormattedRedstonePrice is OracleMiddlewareWithRedstoneFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Return the correct price and timestamp
     * @custom:given A valid Redstone update with a known timestamp and price
     * @custom:and The block timestamp is equal to the Redstone timestamp + `_redstoneRecentPriceDelay`
     * @custom:when The `getFormattedRedstonePrice` function is called with a target timestamp equal to the Redstone
     * timestamp
     * @custom:or The `getFormattedRedstonePrice` function is called with a target timestamp of 0
     * @custom:then It should return the Redstone price and timestamp
     */
    function test_extractPriceUpdateTimestamp() public {
        vm.warp(REDSTONE_ETH_TIMESTAMP + oracleMiddleware.getRedstoneRecentPriceDelay());

        RedstonePriceInfo memory res = oracleMiddleware.i_getFormattedRedstonePrice(
            REDSTONE_ETH_TIMESTAMP, oracleMiddleware.getDecimals(), REDSTONE_ETH_DATA
        );
        assertEq(res.timestamp, REDSTONE_ETH_TIMESTAMP, "targetTimestamp = Redstone timestamp: timestamp");
        assertEq(res.price, REDSTONE_ETH_PRICE, "targetTimestamp = Redstone timestamp: price");

        res = oracleMiddleware.i_getFormattedRedstonePrice(0, oracleMiddleware.getDecimals(), REDSTONE_ETH_DATA);
        assertEq(res.timestamp, REDSTONE_ETH_TIMESTAMP, "targetTimestamp = 0: timestamp");
        assertEq(res.price, REDSTONE_ETH_PRICE, "targetTimestamp = 0: price");
    }

    /**
     * @custom:scenario Revert when the price update timestamp is older than `_redstoneRecentPriceDelay` seconds
     * @custom:given The Redstone price update is `_redstoneRecentPriceDelay` + 1 seconds old
     * @custom:when The `getFormattedRedstonePrice` function is called with a target timestamp of 0
     * @custom:then It should revert with `OracleMiddlewarePriceTooOld`
     */
    function test_RevertWhen_extractPriceUpdateTimestampRecentTooOld() public {
        vm.warp(REDSTONE_ETH_TIMESTAMP + oracleMiddleware.getRedstoneRecentPriceDelay() + 1);
        uint8 decimals = oracleMiddleware.getDecimals();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(0, decimals, REDSTONE_ETH_DATA);
    }

    /**
     * @custom:scenario Revert when the price update timestamp is older than specified target timestamp
     * @custom:given A Redstone price update with a known timestamp and price
     * @custom:when The `getFormattedRedstonePrice` function is called with a target timestamp more recent than the
     * Redstone timestamp
     * @custom:then It should revert with `OracleMiddlewarePriceTooOld`
     */
    function test_RevertWhen_extractPriceUpdateTimestampTooOld() public {
        uint8 decimals = oracleMiddleware.getDecimals();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(REDSTONE_ETH_TIMESTAMP + 1, decimals, REDSTONE_ETH_DATA);
    }

    /**
     * @custom:scenario Revert when the price update timestamp is too recent compared to the target timestamp
     * @custom:given A Redstone price update with a known timestamp and price
     * @custom:when The `getFormattedRedstonePrice` function is called with a target timestamp 1 heartbeat before the
     * Redstone timestamp
     * @custom:then It should revert with `OracleMiddlewarePriceTooRecent`
     * @dev Target timestamp + heartbeat represents the external (second) into the interval representing the allowed
     * price extraction window. It is therefore too recent because it representing the maximum + 1 second timestamp that
     * can be accepted
     */
    function test_RevertWhen_extractPriceUpdateTimestampTooRecent() public {
        uint8 decimals = oracleMiddleware.getDecimals();
        uint48 heartbeat = oracleMiddleware.REDSTONE_HEARTBEAT();
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooRecent.selector, REDSTONE_ETH_TIMESTAMP));
        oracleMiddleware.i_getFormattedRedstonePrice(REDSTONE_ETH_TIMESTAMP - heartbeat, decimals, REDSTONE_ETH_DATA);
    }
}
