// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { OracleMiddleware } from "../../../../src/OracleMiddleware/OracleMiddleware.sol";
import { RedstonePriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @title OracleMiddlewareHandler
 * @dev
 */
contract OracleMiddlewareHandler is OracleMiddleware, Test {
    bool internal _mockRedstonePriceZero;

    constructor(address pythContract, bytes32 pythFeedId, address chainlinkPriceFeed, uint256 chainlinkTimeElapsedLimit)
        OracleMiddleware(pythContract, pythFeedId, chainlinkPriceFeed, chainlinkTimeElapsedLimit)
    { }

    function setMockRedstonePriceZero(bool mock) external {
        _mockRedstonePriceZero = mock;
    }

    function i_isPythData(bytes calldata data) external pure returns (bool) {
        return _isPythData(data);
    }
}
