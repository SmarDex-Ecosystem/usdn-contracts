// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";
import { MockPyth } from "test/unit/OracleMiddleware/utils/MockPyth.sol";
import { MockChainlinkOnChain } from "test/unit/OracleMiddleware/utils/MockChainlinkOnChain.sol";

import { OracleMiddleware } from "src/oracleMiddleware/OracleMiddleware.sol";
import { WstETH } from "test/utils/WstEth.sol";

/**
 * @title OracleMiddlewareBaseFixture
 * @dev Utils for testing the oracle middleware
 */
contract OracleMiddlewareBaseFixture is BaseFixture {
    MockPyth mockPyth;
    MockChainlinkOnChain mockChainlinkOnChain;
    OracleMiddleware public oracleMiddleware;
    WstETH public wsteth;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        mockPyth = new MockPyth();
        mockChainlinkOnChain = new MockChainlinkOnChain();
        wsteth = new WstETH();
        oracleMiddleware = new OracleMiddleware(address(mockPyth), 0, address(mockChainlinkOnChain), address(wsteth));
    }

    function test_setUp() public {
        assertEq(address(oracleMiddleware._pyth()), address(mockPyth));
        assertEq(address(oracleMiddleware._priceFeed()), address(mockChainlinkOnChain));

        assertEq(mockPyth.lastPublishTime(), block.timestamp);
        assertEq(mockChainlinkOnChain.lastPublishTime(), block.timestamp);

        /* ----------------------------- Test pyth mock ----------------------------- */
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        PythStructs.PriceFeed[] memory priceFeeds = mockPyth.parsePriceFeedUpdatesUnique(updateData, priceIds, 1000, 0);

        assertEq(priceFeeds.length, 1);
        assertEq(priceFeeds[0].price.price, 2000 * 1e8);
        assertEq(priceFeeds[0].price.conf, 20 * 1e8);
        assertEq(priceFeeds[0].price.expo, 8);
        assertEq(priceFeeds[0].price.publishTime, 1000);

        /* ---------------------- Test chainlink on chain mock ---------------------- */
        (, int256 price,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        assertEq(price, 2000 * 1e8);
        assertEq(updatedAt, block.timestamp);
    }
}
