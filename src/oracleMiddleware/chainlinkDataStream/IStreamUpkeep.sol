// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { Common } from "src/oracleMiddleware/chainlinkDataStream/externalLibraries/Common.sol";
import { IVerifierFeeManager } from "src/oracleMiddleware/chainlinkDataStream/externalLibraries/IVerifierFeeManager.sol";

interface IStreamUpkeep {
    /**
     * @notice This struct represents the a basic priceFeed report from Chainlink data streams.
     * @param feedId The feed ID the report has data for
     * @param validFromTimestamp Earliest timestamp for which price is applicable
     * @param observationsTimestamp Latest timestamp for which price is applicable
     * @param nativeFee Base cost to validate a transaction using the report, denominated in the chain’s native token
     * @param linkFee Base cost to validate a transaction using the report, denominated in LINK
     * @param expiresAt Latest timestamp where the report can be verified on-chain
     * @param price DON consensus median price, carried to 8 decimal places
     */
    struct BasicReport {
        bytes32 feedId;
        uint32 validFromTimestamp;
        uint32 observationsTimestamp;
        uint192 nativeFee;
        uint192 linkFee;
        uint32 expiresAt;
        int192 price;
    }

    /**
     * @notice This struct represents the a premium priceFeed report from Chainlink data streams.
     * @param feedId The feed ID the report has data for
     * @param validFromTimestamp Earliest timestamp for which price is applicable
     * @param observationsTimestamp Latest timestamp for which price is applicable
     * @param nativeFee Base cost to validate a transaction using the report, denominated in the chain’s native token
     * @param linkFee Base cost to validate a transaction using the report, denominated in LINK
     * @param expiresAt Latest timestamp where the report can be verified on-chain
     * @param price DON consensus median price, carried to 8 decimal places
     * @param bid Simulated price impact of a buy order up to the X% depth of liquidity utilisation
     * @param ask Simulated price impact of a sell order up to the X% depth of liquidity utilisation
     */
    struct PremiumReport {
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
     * @notice This struct represents a quote from a Chainlink data streams.
     */
    struct Quote {
        address quoteAddress;
    }
}

/**
 * @title IVerifierFeeManager
 * @author Yashiru
 * @notice Custom interfaces for IVerifierProxy
 */
interface IVerifierProxy {
    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory verifierResponse);

    function s_feeManager() external view returns (IVerifierFeeManager);
}

/**
 * @title IVerifierFeeManager
 * @author Yashiru
 * @notice Custom interfaces for IFeeManager
 */
interface IFeeManager {
    function getFeeAndReward(address subscriber, bytes memory unverifiedReport, address quoteAddress)
        external
        returns (Common.Asset memory, Common.Asset memory, uint256);

    function i_linkAddress() external view returns (address);

    function i_nativeAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}
