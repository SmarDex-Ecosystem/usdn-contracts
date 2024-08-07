// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { OracleMiddlewareWithRedstone } from "../../../../src/OracleMiddleware/OracleMiddlewareWithRedstone.sol";
import { RedstonePriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

contract OracleMiddlewareWithRedstoneHandler is OracleMiddlewareWithRedstone, Test {
    bool internal _mockRedstonePriceZero;

    constructor(
        address pythContract,
        bytes32 pythFeedId,
        bytes32 redstoneFeedId,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit
    )
        OracleMiddlewareWithRedstone(
            pythContract,
            pythFeedId,
            redstoneFeedId,
            chainlinkPriceFeed,
            chainlinkTimeElapsedLimit
        )
    { }

    function setMockRedstonePriceZero(bool mock) external {
        _mockRedstonePriceZero = mock;
    }

    function getOracleNumericValueFromTxMsg(bytes32 feedId) internal view override returns (uint256) {
        if (_mockRedstonePriceZero) {
            return 0;
        }
        return super.getOracleNumericValueFromTxMsg(feedId);
    }

    function i_isPythData(bytes calldata data) external pure returns (bool) {
        return _isPythData(data);
    }

    function i_extractPriceUpdateTimestamp(bytes calldata) external pure returns (uint48) {
        return _extractPriceUpdateTimestamp(); // redstone wants to parse the last argument in calldata
    }

    function i_getFormattedRedstonePrice(uint128 targetTimestamp, uint256 middlewareDecimals, bytes calldata)
        external
        view
        returns (RedstonePriceInfo memory)
    {
        return _getFormattedRedstonePrice(targetTimestamp, middlewareDecimals);
    }
}
