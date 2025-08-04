// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { CommonOracleMiddleware } from "./CommonOracleMiddleware.sol";
import { OracleMiddlewareWithPyth } from "./OracleMiddlewareWithPyth.sol";

/**
 * @title Middleware Implementation For CbBtc Price
 * @notice This contract is used to get the price of CbBtc.
 */
contract CbBtcOracleMiddlewareWithPyth is OracleMiddlewareWithPyth {
    /**
     * @param pythContract The address of the Pyth contract.
     * @param pythPriceID The ID of the ETH Pyth price feed.
     * @param chainlinkPriceFeed The address of the ETH Chainlink price feed.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     */
    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit
    ) OracleMiddlewareWithPyth(pythContract, pythPriceID, chainlinkPriceFeed, chainlinkTimeElapsedLimit) { }

    /**
     * @inheritdoc IBaseOracleMiddleware
     * @notice Parses and validates `data`, returns the corresponding price.
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
        PriceInfo memory btcPrice = super.parseAndValidatePrice(actionId, targetTimestamp, action, data);
        return PriceInfo({ price: btcPrice.price, neutralPrice: btcPrice.neutralPrice, timestamp: btcPrice.timestamp });
    }
}
