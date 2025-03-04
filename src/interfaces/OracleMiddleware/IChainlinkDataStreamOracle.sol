// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IVerifierProxy } from "./IVerifierProxy.sol";

interface IChainlinkDataStreamOracle {
    /**
     * @notice Gets the Chainlink Proxy verifier contract.
     * @return proxyVerifier_ The proxy verifier.
     */
    function getProxyVerifier() external view returns (IVerifierProxy proxyVerifier_);

    /**
     * @notice Gets the supported Chainlink data stream id.
     * @return streamId_ The steam id.
     */
    function getStreamId() external view returns (bytes32 streamId_);

    /**
     * @notice Gets the maximum age of a recent price to be considered valid.
     * @return delay_ The price delay.
     */
    function getDataStreamRecentPriceDelay() external view returns (uint256 delay_);

    /**
     * @notice Gets the supported Chainlink data stream report version.
     * @return version_ The supported version.
     */
    function getReportVersion() external pure returns (uint256 version_);
}
