// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { Common } from "src/oracleMiddleware/chainlinkDataStream/externalLibraries/Common.sol";
import { IVerifierFeeManager } from "src/oracleMiddleware/chainlinkDataStream/externalLibraries/IVerifierFeeManager.sol";

interface IStreamUpkeep {
    struct BasicReport {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native
            // token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified on-chain
        int192 price; // DON consensus median price, carried to 8 decimal places
    }

    struct PremiumReport {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native
            // token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified on-chain
        int192 price; // DON consensus median price, carried to 8 decimal places
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation
    }

    struct Quote {
        address quoteAddress;
    }
}

interface IVerifierProxy {
    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory verifierResponse);

    function s_feeManager() external view returns (IVerifierFeeManager);
}

interface IFeeManager {
    function getFeeAndReward(address subscriber, bytes memory unverifiedReport, address quoteAddress)
        external
        returns (Common.Asset memory, Common.Asset memory, uint256);

    function i_linkAddress() external view returns (address);

    function i_nativeAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}
