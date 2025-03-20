// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import {
    ChainlinkPriceInfo,
    FormattedDataStreamsPrice,
    FormattedPythPrice,
    PriceAdjustment,
    PriceInfo
} from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareWithChainlinkDataStreams } from
    "../interfaces/OracleMiddleware/IOracleMiddlewareWithChainlinkDataStreams.sol";
import { IVerifierProxy } from "../interfaces/OracleMiddleware/IVerifierProxy.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { CommonOracleMiddleware } from "./CommonOracleMiddleware.sol";
import { ChainlinkDataStreamsOracle } from "./oracles/ChainlinkDataStreamsOracle.sol";

/**
 * @title Middleware Between Oracles And The USDN Protocol
 * @notice This contract is used to get the price of an asset from different oracles.
 * It is used by the USDN protocol to get the price of the USDN underlying asset.
 */
contract OracleMiddlewareWithChainlinkDataStreams is
    CommonOracleMiddleware,
    ChainlinkDataStreamsOracle,
    IOracleMiddlewareWithChainlinkDataStreams
{
    /**
     * @param pythContract Address of the Pyth contract.
     * @param pythFeedId The Pyth price feed ID for the asset.
     * @param chainlinkPriceFeed The address of the Chainlink price feed.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     * @param chainlinkProxyVerifierAddress The address of the Chainlink proxy verifier contract.
     * @param chainlinkStreamId The supported Chainlink data stream ID.
     */
    constructor(
        address pythContract,
        bytes32 pythFeedId,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit,
        address chainlinkProxyVerifierAddress,
        bytes32 chainlinkStreamId
    )
        CommonOracleMiddleware(pythContract, pythFeedId, chainlinkPriceFeed, chainlinkTimeElapsedLimit)
        ChainlinkDataStreamsOracle(chainlinkProxyVerifierAddress, chainlinkStreamId)
    { }

    /* -------------------------------------------------------------------------- */
    /*                           Public view functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IBaseOracleMiddleware
    function validationCost(bytes calldata data, Types.ProtocolAction)
        public
        view
        override(CommonOracleMiddleware, IBaseOracleMiddleware)
        returns (uint256 result_)
    {
        if (data.length == 0) {
            return 0;
        } else if (_isPythData(data)) {
            return _getPythUpdateFee(data);
        } else {
            return _getChainlinkDataStreamFeeData(data).amount;
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStreams
    function setDataStreamsRecentPriceDelay(uint64 newDelay) external onlyRole(ADMIN_ROLE) {
        if (newDelay < 10 seconds) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        if (newDelay > 10 minutes) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        _dataStreamsRecentPriceDelay = newDelay;

        emit DataStreamsRecentPriceDelayUpdated(newDelay);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc CommonOracleMiddleware
    function _getLowLatencyPrice(
        bytes calldata payload,
        uint128 actionTimestamp,
        PriceAdjustment dir,
        uint128 targetLimit
    ) internal virtual override returns (PriceInfo memory price_) {
        // if actionTimestamp is 0 we're performing a liquidation or a initiate
        // action and we don't add the validation delay
        if (actionTimestamp > 0) {
            // add the validation delay to the action timestamp to get
            // the timestamp of the price data used to validate
            actionTimestamp += uint128(_validationDelay);
        }

        FormattedDataStreamsPrice memory formattedPrice =
            _getChainlinkDataStreamPrice(payload, actionTimestamp, targetLimit);
        price_ = _adjustDataStreamPrice(formattedPrice, dir);
    }

    /**
     * @inheritdoc CommonOracleMiddleware
     * @dev If the data parameter is not empty, validate the price with the low latency oracle. Else, get the on-chain
     * price from {ChainlinkOracle} and compare its timestamp with the latest seen Pyth price (cached). If Pyth is more
     * recent, we return it. Otherwise, we return the Chainlink price. For the latter, we don't have a price adjustment,
     * so both `neutralPrice` and `price` are equal.
     */
    function _getInitiateActionPrice(bytes calldata data, PriceAdjustment dir)
        internal
        override
        returns (PriceInfo memory price_)
    {
        // if data is not empty, use Chainlink data streams
        if (data.length > 0) {
            // since we use this function for `initiate` type actions which pass `targetTimestamp = block.timestamp`,
            // we should pass `0` to the function below to signal that we accept any recent price
            return _getLowLatencyPrice(data, 0, dir, 0);
        }

        // Chainlink calls do not require a fee
        if (msg.value > 0) {
            revert OracleMiddlewareIncorrectFee();
        }

        ChainlinkPriceInfo memory chainlinkOnChainPrice = _getFormattedChainlinkLatestPrice(MIDDLEWARE_DECIMALS);

        // check if the cached pyth price is more recent and return it instead
        FormattedPythPrice memory latestPythPrice = _getLatestStoredPythPrice(MIDDLEWARE_DECIMALS);
        if (chainlinkOnChainPrice.timestamp <= latestPythPrice.publishTime) {
            // we use the same price age limit as for Chainlink here
            if (latestPythPrice.publishTime < block.timestamp - _timeElapsedLimit) {
                revert OracleMiddlewarePriceTooOld(latestPythPrice.publishTime);
            }
            return _convertPythPrice(latestPythPrice);
        }

        // if the price equals PRICE_TOO_OLD then the tolerated time elapsed for price validity was exceeded, revert
        if (chainlinkOnChainPrice.price == PRICE_TOO_OLD) {
            revert OracleMiddlewarePriceTooOld(chainlinkOnChainPrice.timestamp);
        }

        // if the price is negative or zero, revert
        if (chainlinkOnChainPrice.price <= 0) {
            revert OracleMiddlewareWrongPrice(chainlinkOnChainPrice.price);
        }

        price_ = PriceInfo({
            price: uint256(chainlinkOnChainPrice.price),
            neutralPrice: uint256(chainlinkOnChainPrice.price),
            timestamp: chainlinkOnChainPrice.timestamp
        });
    }

    /// @inheritdoc CommonOracleMiddleware
    function _getLiquidationPrice(bytes calldata data) internal virtual override returns (PriceInfo memory price_) {
        if (_isPythData(data)) {
            FormattedPythPrice memory pythPrice = _getFormattedPythPrice(data, 0, MIDDLEWARE_DECIMALS, 0);
            return _convertPythPrice(pythPrice);
        }

        FormattedDataStreamsPrice memory formattedPrice = _getChainlinkDataStreamPrice(data, 0, 0);
        price_ = _adjustDataStreamPrice(formattedPrice, PriceAdjustment.None);
    }

    /**
     * @notice Converts a formatted Pyth price into a PriceInfo.
     * @param pythPrice The formatted Pyth price containing the price and publish time.
     * @return price_ The PriceInfo with the price, neutral price, and timestamp set from the Pyth price data.
     */
    function _convertPythPrice(FormattedPythPrice memory pythPrice) internal pure returns (PriceInfo memory price_) {
        price_ = PriceInfo({ price: pythPrice.price, neutralPrice: pythPrice.price, timestamp: pythPrice.publishTime });
    }

    /**
     * @notice Applies the ask, bid or price according to the `dir` direction.
     * @param formattedPrice The Chainlink data streams formatted price.
     * @param dir The direction to adjust the price.
     * @return price_ The adjusted price according to the direction.
     */
    function _adjustDataStreamPrice(FormattedDataStreamsPrice memory formattedPrice, PriceAdjustment dir)
        internal
        pure
        returns (PriceInfo memory price_)
    {
        // cast are safe since checks was made in `_getChainlinkDataStreamPrice`
        if (dir == PriceAdjustment.Down) {
            price_.price = formattedPrice.bid;
        } else if (dir == PriceAdjustment.Up) {
            price_.price = formattedPrice.ask;
        } else {
            price_.price = formattedPrice.price;
        }

        price_.timestamp = formattedPrice.timestamp;
        price_.neutralPrice = formattedPrice.price;
    }
}
