// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { OracleMiddlewareWithDataStreams } from "../../../../src/OracleMiddleware/OracleMiddlewareWithDataStreams.sol";
import { OracleMiddlewareWithPyth } from "../../../../src/OracleMiddleware/OracleMiddlewareWithPyth.sol";
import { IFeeManager } from "../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";
import {
    FormattedDataStreamsPrice,
    FormattedPythPrice,
    PriceAdjustment,
    PriceInfo
} from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

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

contract OracleMiddlewareWithDataStreamsHandler is OracleMiddlewareWithDataStreams, Test {
    constructor(
        address pythContract,
        bytes32 pythFeedId,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit,
        address chainlinkProxyVerifierAddress,
        bytes32 chainlinkStreamId
    )
        OracleMiddlewareWithDataStreams(
            pythContract,
            pythFeedId,
            chainlinkPriceFeed,
            chainlinkTimeElapsedLimit,
            chainlinkProxyVerifierAddress,
            chainlinkStreamId
        )
    { }

    /* -------------------------------------------------------------------------- */
    /*                         ChainlinkDataStreamsOracle                         */
    /* -------------------------------------------------------------------------- */

    function i_getChainlinkDataStreamPrice(bytes calldata payload, uint128 targetTimestamp, uint128 targetLimit)
        external
        payable
        returns (FormattedDataStreamsPrice memory formattedPrice_)
    {
        return _getChainlinkDataStreamPrice(payload, targetTimestamp, targetLimit);
    }

    function i_getChainlinkDataStreamFeeData(bytes calldata payload)
        external
        view
        returns (IFeeManager.Asset memory feeData_)
    {
        return _getChainlinkDataStreamFeeData(payload);
    }

    /* -------------------------------------------------------------------------- */
    /*                  OracleMiddlewareWithDataStreams                  */
    /* -------------------------------------------------------------------------- */

    function i_getLowLatencyPrice(
        bytes calldata payload,
        uint128 actionTimestamp,
        PriceAdjustment dir,
        uint128 targetLimit
    ) external payable returns (PriceInfo memory price_) {
        return _getLowLatencyPrice(payload, actionTimestamp, dir, targetLimit);
    }

    function i_getInitiateActionPrice(bytes calldata data, PriceAdjustment dir)
        external
        payable
        returns (PriceInfo memory price_)
    {
        return _getInitiateActionPrice(data, dir);
    }

    function i_getLiquidationPrice(bytes calldata data) external payable returns (PriceInfo memory price_) {
        return _getLiquidationPrice(data);
    }

    function i_adjustDataStreamPrice(FormattedDataStreamsPrice memory formattedReport, PriceAdjustment dir)
        external
        pure
        returns (PriceInfo memory price_)
    {
        return _adjustDataStreamPrice(formattedReport, dir);
    }
}
