// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IOracleMiddleware } from "../interfaces/OracleMiddleware/IOracleMiddleware.sol";
import {
    ChainlinkPriceInfo,
    ConfidenceInterval,
    FormattedPythPrice,
    PriceInfo
} from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { CommonOracleMiddleware } from "./CommonOracleMiddleware.sol";

/**
 * @title Middleware Between Oracles And The USDN Protocol
 * @notice This contract is used to get the price of an asset from different oracles.
 * It is used by the USDN protocol to get the price of the USDN underlying asset.
 */
contract OracleMiddleware is CommonOracleMiddleware, IOracleMiddleware {
    /// @inheritdoc IOracleMiddleware
    uint16 public constant BPS_DIVISOR = 10_000;

    /// @inheritdoc IOracleMiddleware
    uint16 public constant MAX_CONF_RATIO = BPS_DIVISOR * 2;

    /// @notice Ratio to applied to the Pyth confidence interval (in basis points).
    uint16 internal _confRatioBps = 4000; // to divide by BPS_DIVISOR

    /**
     * @param pythContract Address of the Pyth contract.
     * @param pythFeedId The Pyth price feed ID for the asset.
     * @param chainlinkPriceFeed Address of the Chainlink price feed.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     */
    constructor(address pythContract, bytes32 pythFeedId, address chainlinkPriceFeed, uint256 chainlinkTimeElapsedLimit)
        CommonOracleMiddleware(pythContract, pythFeedId, chainlinkPriceFeed, chainlinkTimeElapsedLimit)
    { }

    /* -------------------------------------------------------------------------- */
    /*                           Public view functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function getConfRatioBps() external view returns (uint16 ratio_) {
        return _confRatioBps;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function setConfRatio(uint16 newConfRatio) external onlyRole(ADMIN_ROLE) {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert OracleMiddlewareConfRatioTooHigh();
        }

        _confRatioBps = newConfRatio;

        emit ConfRatioUpdated(newConfRatio);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc CommonOracleMiddleware
    function _getLowLatencyPrice(
        bytes calldata data,
        uint128 actionTimestamp,
        ConfidenceInterval dir,
        uint128 targetLimit
    ) internal virtual override returns (PriceInfo memory price_) {
        // if actionTimestamp is 0 we're performing a liquidation and we don't add the validation delay
        if (actionTimestamp > 0) {
            // add the validation delay to the action timestamp to get the timestamp of the price data used to
            // validate
            actionTimestamp += uint128(_validationDelay);
        }

        FormattedPythPrice memory pythPrice =
            _getFormattedPythPrice(data, actionTimestamp, MIDDLEWARE_DECIMALS, targetLimit);
        price_ = _adjustPythPrice(pythPrice, dir);
    }

    /// @inheritdoc CommonOracleMiddleware
    function _getInitiateActionPrice(bytes calldata data, ConfidenceInterval dir)
        internal
        override
        returns (PriceInfo memory price_)
    {
        // if data is not empty, use pyth
        if (data.length > 0) {
            // since we use this function for `initiate` type actions which pass `targetTimestamp = block.timestamp`,
            // we should pass `0` to the function below to signal that we accept any recent price
            return _getLowLatencyPrice(data, 0, dir, 0);
        }

        // chainlink calls do not require a fee
        if (msg.value > 0) {
            revert OracleMiddlewareIncorrectFee();
        }

        ChainlinkPriceInfo memory chainlinkOnChainPrice = _getFormattedChainlinkLatestPrice(MIDDLEWARE_DECIMALS);

        // check if the cached pyth price is more recent and return it instead
        FormattedPythPrice memory latestPythPrice = _getLatestStoredPythPrice(MIDDLEWARE_DECIMALS);
        if (chainlinkOnChainPrice.timestamp <= latestPythPrice.publishTime) {
            // we use the same price age limit as for chainlink here
            if (latestPythPrice.publishTime < block.timestamp - _timeElapsedLimit) {
                revert OracleMiddlewarePriceTooOld(latestPythPrice.publishTime);
            }
            return _adjustPythPrice(latestPythPrice, dir);
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

    /**
     * @notice Applies the confidence interval in the `dir` direction, scaled by the configured {_confRatioBps}.
     * @param pythPrice The formatted Pyth price object.
     * @param dir The direction of the confidence interval to apply.
     * @return price_ The adjusted price according to the confidence interval and confidence ratio.
     */
    function _adjustPythPrice(FormattedPythPrice memory pythPrice, ConfidenceInterval dir)
        internal
        view
        returns (PriceInfo memory price_)
    {
        if (dir == ConfidenceInterval.Down) {
            uint256 adjust = (pythPrice.conf * _confRatioBps) / BPS_DIVISOR;
            if (adjust >= pythPrice.price) {
                // avoid underflow or zero price due to confidence interval adjustment
                price_.price = 1;
            } else {
                // strictly positive
                unchecked {
                    price_.price = pythPrice.price - adjust;
                }
            }
        } else if (dir == ConfidenceInterval.Up) {
            price_.price = pythPrice.price + ((pythPrice.conf * _confRatioBps) / BPS_DIVISOR);
        } else {
            price_.price = pythPrice.price;
        }

        price_.timestamp = pythPrice.publishTime;
        price_.neutralPrice = pythPrice.price;
    }
}
