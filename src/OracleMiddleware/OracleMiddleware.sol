// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ChainlinkOracle } from "src/OracleMiddleware/oracles/ChainlinkOracle.sol";
import { PythOracle } from "src/OracleMiddleware/oracles/PythOracle.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import {
    PriceInfo,
    ChainlinkPriceInfo,
    ConfidenceInterval,
    FormattedPythPrice
} from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";

/**
 * @title OracleMiddleware contract
 * @notice This contract is used to get the price of an asset from different price oracle.
 * It is used by the USDN protocol to get the price of the USDN underlying asset.
 * @dev This contract is a middleware between the USDN protocol and the price oracles.
 */
contract OracleMiddleware is IOracleMiddleware, PythOracle, ChainlinkOracle, Ownable {
    uint256 internal _validationDelay = 24 seconds;

    /// @notice confidence ratio denominator
    uint16 private constant CONF_RATIO_DENOM = 10_000;
    /// @notice confidence ratio: up to 200%
    uint16 private constant MAX_CONF_RATIO = CONF_RATIO_DENOM * 2;

    /// @notice confidence ratio: default 40%
    uint16 private _confRatio = 4000; // to divide by CONF_RATIO_DENOM

    /// @notice The number of decimals for the returned price
    uint8 internal constant MIDDLEWARE_DECIMALS = 18;

    /**
     * @param pythContract Address of the Pyth contract
     * @param pythPriceID The price ID of the asset in Pyth
     * @param chainlinkPriceFeed Address of the Chainlink price feed
     * @param chainlinkTimeElapsedLimit Elapsed time tolerated for chainlink's data validity
     */
    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit
    )
        PythOracle(pythContract, pythPriceID)
        ChainlinkOracle(chainlinkPriceFeed, chainlinkTimeElapsedLimit)
        Ownable(msg.sender)
    { }

    /* -------------------------------------------------------------------------- */
    /*                           Public view functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        public
        payable
        virtual
        returns (PriceInfo memory price_)
    {
        if (action == ProtocolAction.None) {
            return _getLowLatencyPrice(data, targetTimestamp, ConfidenceInterval.None);
        } else if (action == ProtocolAction.Initialize) {
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == ProtocolAction.ValidateDeposit) {
            // Use the lowest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return _getLowLatencyPrice(data, targetTimestamp, ConfidenceInterval.Down);
        } else if (action == ProtocolAction.ValidateWithdrawal) {
            // Use the highest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return _getLowLatencyPrice(data, targetTimestamp, ConfidenceInterval.Up);
        } else if (action == ProtocolAction.ValidateOpenPosition) {
            // Use the highest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return _getLowLatencyPrice(data, targetTimestamp, ConfidenceInterval.Up);
        } else if (action == ProtocolAction.ValidateClosePosition) {
            // Use the lowest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return _getLowLatencyPrice(data, targetTimestamp, ConfidenceInterval.Down);
        } else if (action == ProtocolAction.Liquidation) {
            // Special case, if we pass a timestamp of zero, then we accept all prices newer than `_recentPriceDelay`
            return _getLowLatencyPrice(data, 0, ConfidenceInterval.None);
        } else if (action == ProtocolAction.InitiateDeposit) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Down);
        } else if (action == ProtocolAction.InitiateWithdrawal) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Up);
        } else if (action == ProtocolAction.InitiateOpenPosition) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Up);
        } else if (action == ProtocolAction.InitiateClosePosition) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Down);
        }
    }

    /// @inheritdoc IOracleMiddleware
    function getValidationDelay() external view returns (uint256) {
        return _validationDelay;
    }

    /// @inheritdoc IOracleMiddleware
    function getDecimals() external pure returns (uint8) {
        return MIDDLEWARE_DECIMALS;
    }

    /// @inheritdoc IOracleMiddleware
    function getMaxConfRatio() external pure returns (uint16) {
        return MAX_CONF_RATIO;
    }

    /// @inheritdoc IOracleMiddleware
    function getConfRatioDenom() external pure returns (uint16) {
        return CONF_RATIO_DENOM;
    }

    /// @inheritdoc IOracleMiddleware
    function getConfRatio() external view returns (uint16) {
        return _confRatio;
    }

    /// @inheritdoc IOracleMiddleware
    function validationCost(bytes calldata data, ProtocolAction) public view virtual returns (uint256 result_) {
        if (data.length > 0) {
            result_ = _getPythUpdateFee(data);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Get the price from the low-latency oracle (at the moment only Pyth, later maybe others might be supported).
     * @param data The signed price update data.
     * @param actionTimestamp The timestamp of the action corresponding to the price. If zero, then we must accept all
     * recent prices according to `_recentPriceDelay`.
     * @param dir The direction for the confidence interval adjusted price.
     * @return price_ The price from the low-latency oracle, adjusted according to the confidence interval direction.
     */
    function _getLowLatencyPrice(bytes calldata data, uint128 actionTimestamp, ConfidenceInterval dir)
        internal
        returns (PriceInfo memory price_)
    {
        // If actionTimestamp is 0 we're performing a liquidation and we don't add the validation delay
        if (actionTimestamp > 0) {
            // Add the validation delay to the action timestamp to get the timestamp of the price data used to
            // validate
            actionTimestamp += uint128(_validationDelay);
        }
        FormattedPythPrice memory pythPrice = _getFormattedPythPrice(data, actionTimestamp, MIDDLEWARE_DECIMALS);

        price_ = _adjustPythPrice(pythPrice, dir);
    }

    /**
     * @notice Get the price for an initiate action of the protocol.
     * @dev If the data parameter is not empty, validate the price with PythOracle. Else, get the on-chain price from
     * Chainlink and compare its timestamp with the latest seen Pyth price (cached). If Pyth is more recent, we return
     * it. Otherwise we return the chainlink price. In case of chainlink price, we don't have a confidence interval and
     * so both `neutralPrice` and `price` are equal.
     * @param data An optional VAA from Pyth
     * @param dir The direction for applying the confidence interval (in case we use a Pyth price)
     * @return price_ The price to use for the user action
     */
    function _getInitiateActionPrice(bytes calldata data, ConfidenceInterval dir)
        internal
        returns (PriceInfo memory price_)
    {
        // If data is not empty, use pyth
        if (data.length > 0) {
            // since we use this function for `initiate` type actions which pass `targetTimestamp = block.timestamp`,
            // we should pass `0` to the function below to signal that we accept any recent price
            return _getLowLatencyPrice(data, 0, dir);
        }

        // Chainlink calls do not require a fee
        if (msg.value > 0) {
            revert OracleMiddlewareIncorrectFee();
        }

        ChainlinkPriceInfo memory chainlinkOnChainPrice = _getFormattedChainlinkPrice(MIDDLEWARE_DECIMALS);

        // check if the cached pyth price is more recent and return it instead
        FormattedPythPrice memory latestPythPrice = _getLatestStoredPythPrice(MIDDLEWARE_DECIMALS);
        if (chainlinkOnChainPrice.timestamp <= latestPythPrice.publishTime) {
            // We use the same price age limit as for chainlink here
            if (latestPythPrice.publishTime < block.timestamp - _timeElapsedLimit) {
                revert OracleMiddlewarePriceTooOld(latestPythPrice.publishTime);
            }
            return _adjustPythPrice(latestPythPrice, dir);
        }

        // If the price equals PRICE_TOO_OLD then the tolerated time elapsed for price validity was exceeded, revert.
        if (chainlinkOnChainPrice.price == PRICE_TOO_OLD) {
            revert OracleMiddlewarePriceTooOld(chainlinkOnChainPrice.timestamp);
        }

        // If the price is negative or zero, revert.
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
     * @notice Apply the confidence interval in the `dir` direction, scaling it by the configured `_confRatio`.
     * @param pythPrice The formatted Pyth price object.
     * @param dir The direction to apply the confidence interval.
     */
    function _adjustPythPrice(FormattedPythPrice memory pythPrice, ConfidenceInterval dir)
        internal
        view
        returns (PriceInfo memory price_)
    {
        if (dir == ConfidenceInterval.Down) {
            uint256 adjust = (pythPrice.conf * _confRatio) / CONF_RATIO_DENOM;
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
            price_.price = pythPrice.price + ((pythPrice.conf * _confRatio) / CONF_RATIO_DENOM);
        } else {
            price_.price = pythPrice.price;
        }

        price_.timestamp = pythPrice.publishTime;
        price_.neutralPrice = pythPrice.price;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function setValidationDelay(uint256 newValidationDelay) external onlyOwner {
        _validationDelay = newValidationDelay;

        emit ValidationDelayUpdated(newValidationDelay);
    }

    /// @inheritdoc IOracleMiddleware
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external onlyOwner {
        _timeElapsedLimit = newTimeElapsedLimit;

        emit TimeElapsedLimitUpdated(newTimeElapsedLimit);
    }

    /// @inheritdoc IOracleMiddleware
    function setRecentPriceDelay(uint64 newDelay) external onlyOwner {
        if (newDelay < 10 seconds) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        if (newDelay > 10 minutes) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        _recentPriceDelay = newDelay;

        emit RecentPriceDelayUpdated(newDelay);
    }

    /// @inheritdoc IOracleMiddleware
    function setConfRatio(uint16 newConfRatio) external onlyOwner {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert OracleMiddlewareConfRatioTooHigh();
        }

        _confRatio = newConfRatio;

        emit ConfRatioUpdated(newConfRatio);
    }

    /// @inheritdoc IOracleMiddleware
    function withdrawEther(address to) external onlyOwner {
        (bool success,) = payable(to).call{ value: address(this).balance }("");
        if (!success) {
            revert OracleMiddlewareTransferFailed(to);
        }
    }
}
