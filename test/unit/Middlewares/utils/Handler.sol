// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { OracleMiddlewareWithPyth } from "../../../../src/OracleMiddleware/OracleMiddlewareWithPyth.sol";

contract OracleMiddlewareHandler is OracleMiddlewareWithPyth, Test {
    bool internal _mockRedstonePriceZero;

    constructor(address pythContract, bytes32 pythFeedId, address chainlinkPriceFeed, uint256 chainlinkTimeElapsedLimit)
        OracleMiddlewareWithPyth(pythContract, pythFeedId, chainlinkPriceFeed, chainlinkTimeElapsedLimit)
    { }

    function setMockRedstonePriceZero(bool mock) external {
        _mockRedstonePriceZero = mock;
    }

    function i_isPythData(bytes calldata data) external pure returns (bool) {
        return _isPythData(data);
    }
}
