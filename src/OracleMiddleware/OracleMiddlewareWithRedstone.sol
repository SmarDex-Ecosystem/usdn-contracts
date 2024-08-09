// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {
    ChainlinkPriceInfo,
    ConfidenceInterval,
    FormattedPythPrice,
    PriceInfo,
    RedstonePriceInfo
} from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareWithRedstone } from "../interfaces/OracleMiddleware/IOracleMiddlewareWithRedstone.sol";
import { OracleMiddleware } from "./OracleMiddleware.sol";
import { RedstoneOracle } from "./oracles/RedstoneOracle.sol";

/**
 * @title OracleMiddleware contract
 * @notice This contract is used to get the price of an asset from different price oracle
 * It is used by the USDN protocol to get the price of the USDN underlying asset
 * @dev This contract is a middleware between the USDN protocol and the price oracles
 */
contract OracleMiddlewareWithRedstone is IOracleMiddlewareWithRedstone, OracleMiddleware, RedstoneOracle {
    /// @notice The penalty for using a non-Pyth price with low latency oracle, in basis points: default 0.25%
    uint16 internal _penaltyBps = 25; // to divide by BPS_DIVISOR

    /**
     * @param pythContract Address of the Pyth contract
     * @param pythFeedId The Pyth price feed ID for the asset
     * @param redstoneFeedId The Redstone price feed ID for the asset
     * @param chainlinkPriceFeed Address of the Chainlink price feed
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale
     */
    constructor(
        address pythContract,
        bytes32 pythFeedId,
        bytes32 redstoneFeedId,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit
    )
        OracleMiddleware(pythContract, pythFeedId, chainlinkPriceFeed, chainlinkTimeElapsedLimit)
        RedstoneOracle(redstoneFeedId)
    { }

    /* -------------------------------------------------------------------------- */
    /*                           Public view functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddlewareWithRedstone
    function getPenaltyBps() external view returns (uint16) {
        return _penaltyBps;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc OracleMiddleware
     * @dev Get the price from the low-latency oracle (Pyth or Redstone)
     * @param data The signed price update data
     * @param actionTimestamp The timestamp of the action corresponding to the price. If zero, then we must accept all
     * recent prices according to `_pythRecentPriceDelay` or `_redstoneRecentPriceDelay`
     * @param dir The direction for the confidence interval adjusted price
     * @param targetLimit The maximum timestamp when a low-latency price should be used (can be zero if
     * `actionTimestamp` is zero)
     * @return price_ The price from the low-latency oracle, adjusted according to the confidence interval direction
     */
    function _getLowLatencyPrice(
        bytes calldata data,
        uint128 actionTimestamp,
        ConfidenceInterval dir,
        uint128 targetLimit
    ) internal override returns (PriceInfo memory price_) {
        // if actionTimestamp is 0 we're performing a liquidation and we don't add the validation delay
        if (actionTimestamp > 0) {
            // add the validation delay to the action timestamp to get the timestamp of the price data used to
            // validate
            actionTimestamp += uint128(_validationDelay);
        }

        if (_isPythData(data)) {
            FormattedPythPrice memory pythPrice =
                _getFormattedPythPrice(data, actionTimestamp, MIDDLEWARE_DECIMALS, targetLimit);
            price_ = _adjustPythPrice(pythPrice, dir);
        } else {
            // note: redstone automatically retrieves data from the end of the calldata, no need to pass the pointer
            RedstonePriceInfo memory redstonePrice = _getFormattedRedstonePrice(actionTimestamp, MIDDLEWARE_DECIMALS);
            price_ = _adjustRedstonePrice(redstonePrice, dir);
            // sanity check the order of magnitude of the redstone price against chainlink
            // if the redstone price is more than 3x the chainlink price or less than a third, we consider that it's
            // not reliable
            ChainlinkPriceInfo memory chainlinkPrice = _getFormattedChainlinkLatestPrice(MIDDLEWARE_DECIMALS);
            // we check that the chainlink price is valid and not too old
            if (chainlinkPrice.price > 0) {
                if (price_.price > uint256(chainlinkPrice.price) * 3) {
                    revert OracleMiddlewareRedstoneSafeguard();
                }
                if (price_.price < uint256(chainlinkPrice.price) / 3) {
                    revert OracleMiddlewareRedstoneSafeguard();
                }
            }
        }
    }

    /**
     * @notice Apply the confidence interval in the `dir` direction, applying the penalty for non-Pyth oracles
     * @param redstonePrice The formatted Redstone price object
     * @param dir The direction to apply the confidence interval
     * @return price_ The adjusted price according to the confidence interval and penalty
     */
    function _adjustRedstonePrice(RedstonePriceInfo memory redstonePrice, ConfidenceInterval dir)
        internal
        view
        returns (PriceInfo memory price_)
    {
        if (dir == ConfidenceInterval.Down) {
            price_.price = redstonePrice.price - (redstonePrice.price * _penaltyBps / BPS_DIVISOR);
        } else if (dir == ConfidenceInterval.Up) {
            price_.price = redstonePrice.price + (redstonePrice.price * _penaltyBps / BPS_DIVISOR);
        } else {
            price_.price = redstonePrice.price;
        }
        price_.neutralPrice = redstonePrice.price;
        price_.timestamp = redstonePrice.timestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddlewareWithRedstone
    function setRedstoneRecentPriceDelay(uint48 newDelay) external onlyOwner {
        if (newDelay < 10 seconds) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        if (newDelay > 10 minutes) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        _redstoneRecentPriceDelay = newDelay;

        emit RedstoneRecentPriceDelayUpdated(newDelay);
    }

    /// @inheritdoc IOracleMiddlewareWithRedstone
    function setPenaltyBps(uint16 newPenaltyBps) external onlyOwner {
        // penalty greater than max 10%
        if (newPenaltyBps > 1000) {
            revert OracleMiddlewareInvalidPenaltyBps();
        }
        _penaltyBps = newPenaltyBps;

        emit PenaltyBpsUpdated(newPenaltyBps);
    }
}
