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

    // slither-disable-next-line shadowing-state
    uint8 private constant DECIMALS = 18;

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
    /*                          Price retrieval features                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        public
        payable
        virtual
        returns (PriceInfo memory _result)
    {
        if (action == ProtocolAction.None) {
            return getPythOrChainlinkDataStreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        } else if (action == ProtocolAction.Initialize) {
            return getOnChainPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        } else if (action == ProtocolAction.ValidateDeposit) {
            // Use the lowest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return getPythOrChainlinkDataStreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.Down);
        } else if (action == ProtocolAction.ValidateWithdrawal) {
            // There is no reason to use the confidence interval here
            return getPythOrChainlinkDataStreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        } else if (action == ProtocolAction.ValidateOpenPosition) {
            // Use the highest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return getPythOrChainlinkDataStreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.Up);
        } else if (action == ProtocolAction.ValidateClosePosition) {
            // Use the lowest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return getPythOrChainlinkDataStreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.Down);
        } else if (action == ProtocolAction.Liquidation) {
            // Special case, if we pass a timestamp of zero, then we accept all prices newer than `_recentPriceDelay`
            return getPythOrChainlinkDataStreamPrice(data, 0, ConfidenceInterval.None);
        } else if (action == ProtocolAction.InitiateDeposit) {
            return getOnChainPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        } else if (action == ProtocolAction.InitiateWithdrawal) {
            return getOnChainPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        } else if (action == ProtocolAction.InitiateOpenPosition) {
            return getOnChainPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        } else if (action == ProtocolAction.InitiateClosePosition) {
            return getOnChainPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                    Specialized price retrieval methods                     */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Get the price from Pyth or Chainlink, depending on the data.
     * @param data The data used to get the price.
     * @param actionTimestamp The timestamp of the action corresponding to the price. If zero, then we must accept all
     * recent prices.
     * @param conf The confidence interval to use.
     */
    function getPythOrChainlinkDataStreamPrice(bytes calldata data, uint64 actionTimestamp, ConfidenceInterval conf)
        private
        returns (PriceInfo memory price_)
    {
        // If actionTimestamp is 0 we're performing a liquidation and we don't add the validation delay
        if (actionTimestamp > 0) {
            actionTimestamp += uint64(_validationDelay);
        }
        /**
         * @dev Fetch the price from Pyth, return a price at -1 if it fails
         * Add the validation delay to the action timestamp to get the timestamp of the price data used to
         * validate
         */
        FormattedPythPrice memory pythPrice = getFormattedPythPrice(data, actionTimestamp, DECIMALS);

        if (conf == ConfidenceInterval.Down) {
            price_.price = uint256(pythPrice.price) - pythPrice.conf;
        } else if (conf == ConfidenceInterval.Up) {
            price_.price = uint256(pythPrice.price) + pythPrice.conf;
        } else {
            price_.price = uint256(pythPrice.price);
        }

        price_.timestamp = pythPrice.publishTime;
        price_.neutralPrice = uint256(pythPrice.price);
    }

    /// @dev If the data parameter is not empty, get the price from pyth, else, get it from chainlink.
    function getOnChainPrice(bytes calldata data, uint64 actionTimestamp, ConfidenceInterval conf)
        private
        returns (PriceInfo memory)
    {
        // If data is not empty, use pyth
        if (data.length > 0) {
            return getPythOrChainlinkDataStreamPrice(data, actionTimestamp, conf);
        }

        ChainlinkPriceInfo memory chainlinkOnChainPrice = getFormattedChainlinkPrice(DECIMALS);

        // If the price equals PRICE_TOO_OLD then the tolerated time elapsed for price validity was exceeded, revert.
        if (chainlinkOnChainPrice.price == PRICE_TOO_OLD) {
            revert OracleMiddlewarePriceTooOld(chainlinkOnChainPrice.timestamp);
        }

        // If the price is less than 0, revert.
        if (chainlinkOnChainPrice.price < 0) {
            revert OracleMiddlewareWrongPrice(chainlinkOnChainPrice.price);
        }

        return PriceInfo({
            price: uint256(chainlinkOnChainPrice.price),
            neutralPrice: uint256(chainlinkOnChainPrice.price),
            timestamp: chainlinkOnChainPrice.timestamp
        });
    }

    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function validationDelay() external view returns (uint256) {
        return _validationDelay;
    }

    /// @inheritdoc IOracleMiddleware
    function getChainlinkTimeElapsedLimit() external view returns (uint256) {
        return _timeElapsedLimit;
    }

    /// @notice Returns the number of decimals for the price (constant)
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Returns the ETH cost of one price validation for the given action
     * @dev We don't use the protocol action parameter for now
     * @param data The data used to get the price
     */
    function validationCost(bytes calldata data, ProtocolAction) public view virtual returns (uint256 result_) {
        if (data.length > 0) {
            result_ = getPythUpdateFee(data);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                               Owner features                               */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function updateValidationDelay(uint256 _newValidationDelay) external onlyOwner {
        _validationDelay = _newValidationDelay;
    }

    /// @inheritdoc IOracleMiddleware
    function updateChainlinkTimeElapsedLimit(uint256 timeElapsedLimit) external onlyOwner {
        _timeElapsedLimit = timeElapsedLimit;

        emit TimeElapsedLimitUpdated(timeElapsedLimit);
    }

    /**
     * @notice Set the recent price delay
     * @param newDelay The maximum age of a recent price to be considered valid
     */
    function setRecentPriceDelay(uint64 newDelay) external onlyOwner {
        if (newDelay < 10 seconds) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        if (newDelay > 10 minutes) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        _recentPriceDelay = newDelay;
    }
}
