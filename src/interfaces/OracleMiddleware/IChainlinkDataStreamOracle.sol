// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IVerifierProxy } from "./IVerifierProxy.sol";

interface IChainlinkDataStreamOracle {
    /**
     * @notice Gets the Chainlink Proxy verifier contract.
     * @return proxyVerifier_ The address of the proxy verifier contract.
     */
    function getProxyVerifier() external view returns (IVerifierProxy proxyVerifier_);

    /**
     * @notice Gets the supported Chainlink data stream ID.
     * @return streamId_ The unique identifier for the Chainlink data streams.
     */
    function getStreamId() external view returns (bytes32 streamId_);

    /**
     * @notice Gets the maximum age of a recent price to be considered valid.
     * @return delay_ The maximum acceptable age of a recent price in seconds.
     */
    function getDataStreamRecentPriceDelay() external view returns (uint256 delay_);

    /**
     * @notice Gets the supported Chainlink data streams report version.
     * @return version_ The version number of the supported Chainlink data streams report.
     */
    function getReportVersion() external pure returns (uint256 version_);
}
