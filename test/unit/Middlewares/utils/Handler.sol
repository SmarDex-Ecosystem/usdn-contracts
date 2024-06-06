// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";

import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";

/**
 * @title OracleMiddlewareHandler
 * @dev
 */
contract OracleMiddlewareHandler is OracleMiddleware, Test {
    constructor(
        address pythContract,
        bytes32 pythFeedId,
        bytes32 redstoneFeedId,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit
    ) OracleMiddleware(pythContract, pythFeedId, redstoneFeedId, chainlinkPriceFeed, chainlinkTimeElapsedLimit) { }

    function i_isPythData(bytes calldata data) external pure returns (bool) {
        return _isPythData(data);
    }
}
