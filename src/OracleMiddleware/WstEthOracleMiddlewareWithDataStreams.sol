// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IWstETH } from "../interfaces/IWstETH.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { CommonOracleMiddleware } from "./CommonOracleMiddleware.sol";
import { OracleMiddlewareWithDataStreams } from "./OracleMiddlewareWithDataStreams.sol";

/**
 * @title Middleware Implementation For WstETH Price With Chainlink Data Streams
 * @notice This contract is used to get the price of wstETH from the ETH price or the wstETH price directly.
 */
contract WstEthOracleMiddlewareWithDataStreams is OracleMiddlewareWithDataStreams {
    /// @notice The wstETH contract.
    IWstETH internal immutable _wstETH;

    /**
     * @param pythContract The address of the Pyth contract.
     * @param pythFeedId The ETH/USD Pyth price feed ID for the asset.
     * @param chainlinkPriceFeed The address of the Chainlink ETH/USD price feed.
     * @param wstETH The address of the wstETH contract.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     * @param chainlinkProxyVerifierAddress The address of the Chainlink proxy verifier contract.
     * @param chainlinkStreamId The supported Chainlink wstETH/USD data stream ID.
     */
    constructor(
        address pythContract,
        bytes32 pythFeedId,
        address chainlinkPriceFeed,
        address wstETH,
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
    {
        _wstETH = IWstETH(wstETH);
    }

    /**
     * @inheritdoc IBaseOracleMiddleware
     * @notice Parses and validates `data`, returns the corresponding price data,
     * applying ETH/wstETH ratio if the price is in ETH.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * If needed, the wstETH price is calculated as follows: `ethPrice x stEthPerToken / 1 ether`.
     * A fee amounting to exactly {validationCost} (with the same `data` and `action`) must be sent or the transaction
     * will revert.
     * @param actionId A unique identifier for the current action. This identifier can be used to link an `Initiate`
     * call with the corresponding `Validate` call.
     * @param targetTimestamp The target timestamp for validating the price data. For validation actions, this is the
     * timestamp of the initiation.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data The data to be used to communicate with oracles, the format varies from middleware to middleware and
     * can be different depending on the action.
     * @return result_ The price and timestamp as {IOracleMiddlewareTypes.PriceInfo}.
     */
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) public payable virtual override(IBaseOracleMiddleware, CommonOracleMiddleware) returns (PriceInfo memory) {
        PriceInfo memory oraclePrice = super.parseAndValidatePrice(actionId, targetTimestamp, action, data);

        if (data.length > 32 && !_isPythData(data)) {
            // the price is already in wstETH/USD from the Chainlink data stream
            return oraclePrice;
        }

        uint256 stEthPerToken = _wstETH.stEthPerToken();

        return PriceInfo({
            price: oraclePrice.price * stEthPerToken / 1 ether,
            neutralPrice: oraclePrice.neutralPrice * stEthPerToken / 1 ether,
            timestamp: oraclePrice.timestamp
        });
    }
}
