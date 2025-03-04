// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IFeeManager } from "./IFeeManager.sol";

interface IVerifierProxy {
    /**
     * @notice Represents a data report from a Data Streams stream for v3 schema (crypto streams).
     * @dev The `price`, `bid`, and `ask` values are carried to either 8 or 18 decimal places, depending on the stream.
     * For more information, see https://docs.chain.link/data-streams/crypto-streams and
     * https://docs.chain.link/data-streams/reference/report-schema.
     * @param feedId The stream ID the report has data for.
     * @param validFromTimestamp The earliest timestamp for which price is applicable.
     * @param observationsTimestamp The latest timestamp for which price is applicable.
     * @param nativeFee The base cost to validate a transaction using the report,
     * denominated in the chain’s native token (e.g., WETH/ETH).
     * @param linkFee The base cost to validate a transaction using the report, denominated in LINK.
     * @param expiresAt The latest timestamp where the report can be verified onchain.
     * @param price The DON consensus median price (8 or 18 decimals).
     * @param bid  The simulated price impact of a buy order up to the X% depth of liquidity usage (8 or 18 decimals).
     * @param ask The simulated price impact of a sell order up to the X% depth of liquidity usage (8 or 18 decimals).
     */
    struct ReportV3 {
        bytes32 feedId;
        uint32 validFromTimestamp;
        uint32 observationsTimestamp;
        uint192 nativeFee;
        uint192 linkFee;
        uint32 expiresAt;
        int192 price;
        int192 bid;
        int192 ask;
    }

    /**
     * @notice Gets the fee manager contract.
     * @return feeManager_ The fee manager contract.
     */
    function s_feeManager() external view returns (IFeeManager feeManager_);

    /**
     * @notice Verifies that the data encoded has been signed
     * correctly by routing to the correct verifier, and bills the user if applicable.
     * @param payload The encoded data to be verified, including the signed
     * report.
     * @param parameterPayload The fee metadata for billing.
     * @return verifierResponse The encoded report from the verifier.
     */
    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory verifierResponse);

    /**
     * @notice Bulk verifies that the data encoded has been signed
     * correctly by routing to the correct verifier, and bills the user if applicable.
     * @param payloads The encoded payloads to be verified, including the signed
     * report.
     * @param parameterPayload The fee metadata for billing.
     * @return verifiedReports The encoded reports from the verifier.
     */
    function verifyBulk(bytes[] calldata payloads, bytes calldata parameterPayload)
        external
        payable
        returns (bytes[] memory verifiedReports);

    /**
     * @notice Retrieves the verifier address that verifies reports
     * for a config digest.
     * @param configDigest The config digest to query for.
     * @return verifierAddress The address of the verifier contract that verifies
     * reports for a given config digest.
     */
    function getVerifier(bytes32 configDigest) external view returns (address verifierAddress);
}
