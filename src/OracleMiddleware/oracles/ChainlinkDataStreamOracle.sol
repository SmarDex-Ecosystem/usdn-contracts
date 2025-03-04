// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IFeeManager } from "../../interfaces/OracleMiddleware/IFeeManager.sol";
import { IVerifierProxy } from "../../interfaces/OracleMiddleware/IVerifierProxy.sol";
import { console } from "forge-std/Test.sol";

import { IChainlinkDataStreamOracle } from "../../interfaces/OracleMiddleware/IChainlinkDataStreamOracle.sol";
import { IOracleMiddlewareErrors } from "../../interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @title Contract To Communicate With The Chainlink Data Stream
 * @notice This contract is used to get the price of the asset that corresponds to the stored Chainlink data stream ID.
 * @dev Is implemented by the {OracleMiddleware} contract.
 */
abstract contract ChainlinkDataStreamOracle is IOracleMiddlewareErrors, IChainlinkDataStreamOracle {
    /// @notice The address of the Chainlink proxy verifier contract.
    IVerifierProxy internal immutable PROXY_VERIFIER;

    /// @notice The ID of the Chainlink data stream.
    bytes32 internal immutable STREAM_ID;

    /// @notice The report version.
    uint256 internal constant REPORT_VERSION = 3;

    /// @notice The maximum age of a recent price to be considered valid for chainlink data stream.
    uint256 internal _dataStreamRecentPriceDelay = 45 seconds;

    /**
     * @param verifierAddress The address of the Chainlink proxy verifier contract.
     * @param streamId The ID of the Chainlink data stream.
     */
    constructor(address verifierAddress, bytes32 streamId) {
        PROXY_VERIFIER = IVerifierProxy(verifierAddress);
        STREAM_ID = streamId;
    }

    /// @inheritdoc IChainlinkDataStreamOracle
    function getProxyVerifier() external view returns (IVerifierProxy proxyVerifier_) {
        return PROXY_VERIFIER;
    }

    /// @inheritdoc IChainlinkDataStreamOracle
    function getStreamId() external view returns (bytes32 streamId_) {
        return STREAM_ID;
    }

    /// @inheritdoc IChainlinkDataStreamOracle
    function getDataStreamRecentPriceDelay() external view returns (uint256 delay_) {
        return _dataStreamRecentPriceDelay;
    }

    /// @inheritdoc IChainlinkDataStreamOracle
    function getReportVersion() external pure returns (uint256 version_) {
        return REPORT_VERSION;
    }

    /**
     * @notice Gets the price of the asset with Chainlink data stream.
     * @param payload The full report obtained from the Chainlink data stream API.
     * @param targetTimestamp The target timestamp of the price.
     * If zero, then we accept all recent prices.
     * @return verifiedReport_ The Chainlink verified report.
     */
    function _getChainlinkDataStreamPrice(bytes calldata payload, uint128 targetTimestamp)
        internal
        returns (IVerifierProxy.ReportV3 memory verifiedReport_)
    {
        IFeeManager.Asset memory feeData = _getChainlinkDataStreamFeeData(payload);
        console.log("feeData.amount", feeData.amount);

        // sanity check on the fee requested by the Chainlink fee manager
        if (feeData.amount > 0.01 ether) {
            revert OracleMiddlewareDataStreamFeeSafeguard(feeData.amount);
        }
        if (msg.value != feeData.amount) {
            revert OracleMiddlewareIncorrectFee();
        }

        // verify report
        bytes memory verifiedReportData =
            PROXY_VERIFIER.verify{ value: feeData.amount }(payload, abi.encode(feeData.assetAddress));

        // report version
        uint16 reportVersion = (uint16(uint8(verifiedReportData[0])) << 8) | uint16(uint8(verifiedReportData[1]));
        if (reportVersion != REPORT_VERSION) {
            revert OracleMiddlewareInvalidReportVersion();
        }

        // decode verified report
        verifiedReport_ = abi.decode(verifiedReportData, (IVerifierProxy.ReportV3));

        // stream id
        if (verifiedReport_.feedId != STREAM_ID) {
            revert OracleMiddlewareInvalidStreamId();
        }

        // report timestamp
        if (targetTimestamp == 0) {
            if (verifiedReport_.expiresAt < block.timestamp - _dataStreamRecentPriceDelay) {
                revert OracleMiddlewareDataStreamInvalidTimestamp();
            }
        } else if (targetTimestamp < verifiedReport_.validFromTimestamp || verifiedReport_.expiresAt < targetTimestamp)
        {
            revert OracleMiddlewareDataStreamInvalidTimestamp();
        }

        // report prices
        if (verifiedReport_.price <= 0) {
            revert OracleMiddlewareWrongPrice(verifiedReport_.price);
        }
        if (verifiedReport_.ask <= 0) {
            revert OracleMiddlewareWrongPrice(verifiedReport_.ask);
        }
        if (verifiedReport_.bid <= 0) {
            revert OracleMiddlewareWrongPrice(verifiedReport_.bid);
        }
    }

    /**
     * @notice Gets the fee asset data to update the price feed.
     * @dev The native token fee option will be used.
     * @param payload The data stream payload.
     * @return feeData_ The fee asset data to verify the report.
     */
    function _getChainlinkDataStreamFeeData(bytes calldata payload)
        internal
        view
        returns (IFeeManager.Asset memory feeData_)
    {
        IFeeManager feeManager = PROXY_VERIFIER.s_feeManager();
        if (address(feeManager) != address(0)) {
            address quoteAddress = feeManager.i_nativeAddress();
            (, bytes memory reportData) = abi.decode(payload, (bytes32[3], bytes));
            (feeData_,,) = feeManager.getFeeAndReward(address(this), reportData, quoteAddress);
        }
    }
}
