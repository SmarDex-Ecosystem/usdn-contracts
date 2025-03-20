// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IChainlinkDataStreamsOracle } from "../../interfaces/OracleMiddleware/IChainlinkDataStreamsOracle.sol";
import { IFeeManager } from "../../interfaces/OracleMiddleware/IFeeManager.sol";
import { IOracleMiddlewareErrors } from "../../interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { FormattedDataStreamsPrice } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IVerifierProxy } from "../../interfaces/OracleMiddleware/IVerifierProxy.sol";

/**
 * @title Oracle Middleware for Chainlink Data Streams
 * @notice This contract is used to get the price of the asset that corresponds to the stored Chainlink data streams ID.
 * @dev Is implemented by the {OracleMiddlewareWithChainlinkDataStreams} contract.
 */
abstract contract ChainlinkDataStreamsOracle is IOracleMiddlewareErrors, IChainlinkDataStreamsOracle {
    /// @notice The address of the Chainlink proxy verifier contract.
    IVerifierProxy internal immutable PROXY_VERIFIER;

    /// @notice The ID of the Chainlink data streams.
    bytes32 internal immutable STREAM_ID;

    /// @notice The report version.
    uint256 internal constant REPORT_VERSION = 3;

    /// @notice The maximum age of a recent price to be considered valid for Chainlink data streams.
    uint256 internal _dataStreamsRecentPriceDelay = 45 seconds;

    /**
     * @param verifierAddress The address of the Chainlink proxy verifier contract.
     * @param streamId The ID of the Chainlink data streams.
     */
    constructor(address verifierAddress, bytes32 streamId) {
        PROXY_VERIFIER = IVerifierProxy(verifierAddress);
        STREAM_ID = streamId;
    }

    /// @inheritdoc IChainlinkDataStreamsOracle
    function getProxyVerifier() external view returns (IVerifierProxy proxyVerifier_) {
        return PROXY_VERIFIER;
    }

    /// @inheritdoc IChainlinkDataStreamsOracle
    function getStreamId() external view returns (bytes32 streamId_) {
        return STREAM_ID;
    }

    /// @inheritdoc IChainlinkDataStreamsOracle
    function getDataStreamRecentPriceDelay() external view returns (uint256 delay_) {
        return _dataStreamsRecentPriceDelay;
    }

    /// @inheritdoc IChainlinkDataStreamsOracle
    function getReportVersion() external pure returns (uint256 version_) {
        return REPORT_VERSION;
    }

    /**
     * @notice Gets the price of the asset with Chainlink data streams.
     * @param payload The full report obtained from the Chainlink data streams API.
     * @param targetTimestamp The target timestamp of the price.
     * If zero, then we accept all recent prices.
     * @param targetLimit The most recent timestamp a price can have.
     * Can be zero if `targetTimestamp` is zero.
     * @return formattedPrice_ The Chainlink formatted price.
     */
    function _getChainlinkDataStreamPrice(bytes calldata payload, uint128 targetTimestamp, uint128 targetLimit)
        internal
        returns (FormattedDataStreamsPrice memory formattedPrice_)
    {
        IFeeManager.Asset memory feeData = _getChainlinkDataStreamFeeData(payload);

        // Sanity check on the fee requested by the Chainlink fee manager
        if (feeData.amount > 0.01 ether) {
            revert OracleMiddlewareDataStreamFeeSafeguard(feeData.amount);
        }
        if (msg.value != feeData.amount) {
            revert OracleMiddlewareIncorrectFee();
        }

        // Verify report
        bytes memory verifiedReportData =
            PROXY_VERIFIER.verify{ value: feeData.amount }(payload, abi.encode(feeData.assetAddress));

        // Report version
        uint16 reportVersion = (uint16(uint8(verifiedReportData[0])) << 8) | uint16(uint8(verifiedReportData[1]));
        if (reportVersion != REPORT_VERSION) {
            revert OracleMiddlewareInvalidReportVersion();
        }

        // Decode verified report
        IVerifierProxy.ReportV3 memory verifiedReport = abi.decode(verifiedReportData, (IVerifierProxy.ReportV3));

        // Stream ID
        if (verifiedReport.feedId != STREAM_ID) {
            revert OracleMiddlewareInvalidStreamId();
        }

        // Report timestamp
        if (targetTimestamp == 0) {
            if (verifiedReport.validFromTimestamp < block.timestamp - _dataStreamsRecentPriceDelay) {
                revert OracleMiddlewareDataStreamInvalidTimestamp();
            }
        } else if (
            targetTimestamp < verifiedReport.validFromTimestamp
                || verifiedReport.observationsTimestamp < targetTimestamp
                || targetLimit < verifiedReport.observationsTimestamp
        ) {
            revert OracleMiddlewareDataStreamInvalidTimestamp();
        }

        // Report prices
        if (verifiedReport.price <= 0) {
            revert OracleMiddlewareWrongPrice(verifiedReport.price);
        }
        if (verifiedReport.ask <= 0) {
            revert OracleMiddlewareWrongAskPrice(verifiedReport.ask);
        }
        if (verifiedReport.bid <= 0) {
            revert OracleMiddlewareWrongBidPrice(verifiedReport.bid);
        }

        return FormattedDataStreamsPrice({
            timestamp: uint256(verifiedReport.observationsTimestamp),
            price: uint256(uint192(verifiedReport.price)),
            ask: uint256(uint192(verifiedReport.ask)),
            bid: uint256(uint192(verifiedReport.bid))
        });
    }

    /**
     * @notice Gets the fee asset data to decode the payload.
     * @dev The native token fee option will be used.
     * @param payload The data streams payload (full report).
     * @return feeData_ The fee asset data including the token and the amount required to verify the report.
     */
    function _getChainlinkDataStreamFeeData(bytes calldata payload)
        internal
        view
        returns (IFeeManager.Asset memory feeData_)
    {
        IFeeManager feeManager = PROXY_VERIFIER.s_feeManager();
        if (address(feeManager) == address(0)) {
            return feeData_;
        }
        (, bytes memory reportData) = abi.decode(payload, (bytes32[3], bytes));
        address quoteAddress = feeManager.i_nativeAddress();
        (feeData_,,) = feeManager.getFeeAndReward(address(this), reportData, quoteAddress);
    }
}
