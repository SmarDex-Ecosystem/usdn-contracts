// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ChainlinkPriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ChainlinkOracle } from "./oracles/ChainlinkOracle.sol";
import { PythOracle } from "./oracles/PythOracle.sol";

/**
 * @title Common Middleware Contract
 * @notice This contract serves as a foundational middleware that must be implemented by other middleware contracts.
 */
abstract contract CommonOracleMiddleware is PythOracle, ChainlinkOracle {
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANT                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice The number of decimals for the returned price.
    uint8 internal constant MIDDLEWARE_DECIMALS = 18;

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @param pythContract Address of the Pyth contract.
     * @param pythFeedId The Pyth price feed ID for the asset.
     * @param chainlinkPriceFeed Address of the Chainlink price feed.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     */
    constructor(address pythContract, bytes32 pythFeedId, address chainlinkPriceFeed, uint256 chainlinkTimeElapsedLimit)
        PythOracle(pythContract, pythFeedId)
        ChainlinkOracle(chainlinkPriceFeed, chainlinkTimeElapsedLimit)
    { }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Checks that the given round ID is valid and returns its corresponding price data.
     * @dev Round IDs are not necessarily consecutive, so additional computing can be necessary to find
     * the previous round ID.
     * @param targetLimit The timestamp of the initiate action + {_lowLatencyDelay}.
     * @param roundId The round ID to validate.
     * @return providedRoundPrice_ The price data of the provided round ID.
     */
    function _validateChainlinkRoundId(uint128 targetLimit, uint80 roundId)
        internal
        view
        virtual
        returns (ChainlinkPriceInfo memory providedRoundPrice_)
    {
        providedRoundPrice_ = _getFormattedChainlinkPrice(MIDDLEWARE_DECIMALS, roundId);

        if (providedRoundPrice_.price <= 0) {
            revert OracleMiddlewareWrongPrice(providedRoundPrice_.price);
        }

        (,,, uint256 previousRoundTimestamp,) = _priceFeed.getRoundData(roundId - 1);

        // if the provided round's timestamp is 0, it's possible the aggregator recently changed and there is no data
        // available for the previous round ID in the aggregator. In that case, we accept the given round ID as the
        // sole reference with additional checks to make sure it is not too far from the target timestamp
        if (previousRoundTimestamp == 0) {
            // calculate the provided round's phase ID
            uint80 roundPhaseId = roundId >> 64;
            // calculate the first valid round ID for this phase
            uint80 firstRoundId = (roundPhaseId << 64) + 1;
            // the provided round ID must be the first round ID of the phase, if not, revert
            if (firstRoundId != roundId) {
                revert OracleMiddlewareInvalidRoundId();
            }

            // make sure that the provided round ID is not newer than it should be
            if (providedRoundPrice_.timestamp > targetLimit + _timeElapsedLimit) {
                revert OracleMiddlewareInvalidRoundId();
            }
        } else if (previousRoundTimestamp > targetLimit) {
            // previous round should precede targetLimit
            revert OracleMiddlewareInvalidRoundId();
        }

        if (providedRoundPrice_.timestamp <= targetLimit) {
            revert OracleMiddlewareInvalidRoundId();
        }
    }

    /**
     * @notice Checks if the passed calldata corresponds to a Pyth message.
     * @param data The calldata pointer to the message.
     * @return isPythData_ Whether the data is a valid Pyth message or not.
     */
    function _isPythData(bytes calldata data) internal pure virtual returns (bool isPythData_) {
        if (data.length <= 32) {
            return false;
        }
        // check the first 4 bytes of the data to identify a pyth message
        uint32 magic;
        assembly {
            magic := shr(224, calldataload(data.offset))
        }
        // Pyth magic stands for PNAU (Pyth Network Accumulator Update)
        return magic == 0x504e4155;
    }
}
