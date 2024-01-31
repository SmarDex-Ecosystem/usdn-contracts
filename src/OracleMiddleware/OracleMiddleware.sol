// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { ChainlinkOracle } from "src/OracleMiddleware/oracles/ChainlinkOracle.sol";
import { PythOracle } from "src/OracleMiddleware/oracles/PythOracle.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import {
    PriceInfo,
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
contract OracleMiddleware is IOracleMiddleware, PythOracle, ChainlinkOracle {
    uint256 constant VALIDATION_DELAY = 24 seconds;

    // slither-disable-next-line shadowing-state
    uint8 private constant DECIMALS = 18;

    constructor(address pythContract, bytes32 pythPriceID, address chainlinkPriceFeed)
        PythOracle(pythContract, pythPriceID)
        ChainlinkOracle(chainlinkPriceFeed)
    { }

    /* -------------------------------------------------------------------------- */
    /*                          Price retrieval features                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory)
    {
        if (action == ProtocolAction.None) {
            return getPythOrChainlinkDataStreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.None);
        } else if (action == ProtocolAction.Initialize) {
            // Use chainlink data to make deploiement easier
            return getChainlinkOnChainPrice();
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
            // Use the lowest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies
            return getPythOrChainlinkDataStreamPrice(data, uint64(targetTimestamp), ConfidenceInterval.Down);
        } else if (action == ProtocolAction.InitiateDeposit) {
            return getChainlinkOnChainPrice();
        } else if (action == ProtocolAction.InitiateWithdrawal) {
            return getChainlinkOnChainPrice();
        } else if (action == ProtocolAction.InitiateOpenPosition) {
            return getChainlinkOnChainPrice();
        } else if (action == ProtocolAction.InitiateClosePosition) {
            return getChainlinkOnChainPrice();
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                     Factorised price retrieval methods                     */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Get the price from Pyth or Chainlink, depending on the data.
     * @param data The data used to get the price.
     * @param actionTimestamp The timestamp of the action corresponding to the price.
     * @param conf The confidence interval to use.
     */
    function getPythOrChainlinkDataStreamPrice(bytes calldata data, uint64 actionTimestamp, ConfidenceInterval conf)
        private
        returns (PriceInfo memory price_)
    {
        /**
         * @dev Fetch the price from Pyth, return a price at -1 if it fails
         * Add the validation delay to the action timestamp to get the timestamp of the price data used to
         * validate
         */
        FormattedPythPrice memory pythPrice =
            getFormattedPythPrice(data, actionTimestamp + uint64(VALIDATION_DELAY), DECIMALS);

        if (pythPrice.price != -1) {
            if (conf == ConfidenceInterval.Down) {
                price_.price = uint256(pythPrice.price) - pythPrice.conf;
            } else if (conf == ConfidenceInterval.Up) {
                price_.price = uint256(pythPrice.price) + pythPrice.conf;
            } else {
                price_.price = uint256(pythPrice.price);
            }

            price_.timestamp = pythPrice.publishTime;
            price_.neutralPrice = uint256(pythPrice.price);
        } else {
            revert PythValidationFailed();
        }
    }

    /**
     * @dev Get the price from Chainlink onChain.
     */
    function getChainlinkOnChainPrice() private view returns (PriceInfo memory) {
        return getFormattedChainlinkPrice(DECIMALS);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns the delay (in seconds) between an action timestamp and the
    ///         price data timestamp used to validate that action.
    function validationDelay() external pure returns (uint256) {
        return VALIDATION_DELAY;
    }

    /// @notice Returns the number of decimals for the price (constant)

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice Returns the ETH cost of one price validation for the given action
    function validationCost(bytes calldata data, ProtocolAction action) external view returns (uint256) {
        // TODO: Validate each ConfidenceInterval
        if (action == ProtocolAction.None) {
            return getPythUpdateFee(data);
        } else if (action == ProtocolAction.Initialize) {
            return 0;
        } else if (action == ProtocolAction.ValidateDeposit) {
            return getPythUpdateFee(data);
        } else if (action == ProtocolAction.ValidateWithdrawal) {
            return getPythUpdateFee(data);
        } else if (action == ProtocolAction.ValidateOpenPosition) {
            return getPythUpdateFee(data);
        } else if (action == ProtocolAction.ValidateClosePosition) {
            return getPythUpdateFee(data);
        } else if (action == ProtocolAction.Liquidation) {
            return getPythUpdateFee(data);
        } else if (action == ProtocolAction.InitiateDeposit) {
            return 0;
        } else if (action == ProtocolAction.InitiateWithdrawal) {
            return 0;
        } else if (action == ProtocolAction.InitiateOpenPosition) {
            return 0;
        } else if (action == ProtocolAction.InitiateClosePosition) {
            return 0;
        }
    }
}
