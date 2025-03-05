// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import {
    ChainlinkPriceInfo,
    ConfidenceInterval,
    FormattedPythPrice,
    PriceInfo
} from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOracleMiddlewareWithChainlinkDataStream } from
    "../interfaces/OracleMiddleware/IOracleMiddlewareWithChainlinkDataStream.sol";
import { IVerifierProxy } from "../interfaces/OracleMiddleware/IVerifierProxy.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ChainlinkDataStreamOracle } from "./oracles/ChainlinkDataStreamOracle.sol";
import { ChainlinkOracle } from "./oracles/ChainlinkOracle.sol";
import { PythOracle } from "./oracles/PythOracle.sol";

/**
 * @title Middleware Between Oracles And The USDN Protocol
 * @notice This contract is used to get the price of an asset from different oracles.
 * It is used by the USDN protocol to get the price of the USDN underlying asset.
 */
contract OracleMiddlewareWithChainlinkDataStream is
    IOracleMiddlewareWithChainlinkDataStream,
    PythOracle,
    ChainlinkOracle,
    AccessControlDefaultAdminRules,
    ChainlinkDataStreamOracle
{
    /// @notice The number of decimals for the returned price.
    uint8 internal constant MIDDLEWARE_DECIMALS = 18;

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStream
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @notice The delay (in seconds) between the moment an action is initiated and the timestamp of the
     * price data used to validate that action.
     */
    uint256 internal _validationDelay = 24 seconds;

    /**
     * @notice The amount of time during which a low latency oracle price validation is available.
     * @dev This value should be greater than or equal to `_lowLatencyValidatorDeadline` of the USDN protocol.
     */
    uint16 internal _lowLatencyDelay = 20 minutes;

    /**
     * @param pythContract Address of the Pyth contract.
     * @param pythFeedId The Pyth price feed ID for the asset.
     * @param chainlinkPriceFeed The address of the Chainlink price feed.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     * @param chainlinkProxyVerifierAddress The address of the Chainlink proxy verifier contract.
     * @param chainlinkStreamId The supported Chainlink data stream id.
     */
    constructor(
        address pythContract,
        bytes32 pythFeedId,
        address chainlinkPriceFeed,
        uint256 chainlinkTimeElapsedLimit,
        address chainlinkProxyVerifierAddress,
        bytes32 chainlinkStreamId
    )
        PythOracle(pythContract, pythFeedId)
        ChainlinkOracle(chainlinkPriceFeed, chainlinkTimeElapsedLimit)
        ChainlinkDataStreamOracle(chainlinkProxyVerifierAddress, chainlinkStreamId)
        AccessControlDefaultAdminRules(0, msg.sender)
    {
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Public view functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IBaseOracleMiddleware
    function parseAndValidatePrice(bytes32, uint128 targetTimestamp, Types.ProtocolAction action, bytes calldata data)
        public
        payable
        virtual
        returns (PriceInfo memory price_)
    {
        if (action == Types.ProtocolAction.None) {
            return _getLowLatencyPrice(data, targetTimestamp, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.Initialize) {
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.ValidateDeposit) {
            // use the bid price of the Chainlink data streams then use Chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Down);
        } else if (action == Types.ProtocolAction.ValidateWithdrawal) {
            // use the ask price  of the Chainlink data streams then use Chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Up);
        } else if (action == Types.ProtocolAction.ValidateOpenPosition) {
            // use the ask price  of the Chainlink data streams then use Chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Up);
        } else if (action == Types.ProtocolAction.ValidateClosePosition) {
            // use the bid price of the Chainlink data streams then use Chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Down);
        } else if (action == Types.ProtocolAction.Liquidation) {
            // we accept all prices newer than  `_dataStreamRecentPriceDelay` for Chainlink or
            // `_pythRecentPriceDelay` for Pyth
            return _getLiquidationPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.InitiateDeposit) {
            // if the user chooses to initiate with Chainlink data streams, the neutral price will be used
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.InitiateWithdrawal) {
            // if the user chooses to initiate with Chainlink data streams, the neutral price will be used
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.InitiateOpenPosition) {
            // if the user chooses to initiate with Chainlink data streams, the neutral price will be used
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.InitiateClosePosition) {
            // if the user chooses to initiate with Chainlink data streams, the neutral price will be used
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        }
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getValidationDelay() external view returns (uint256 delay_) {
        return _validationDelay;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getDecimals() external pure returns (uint8 decimals_) {
        return MIDDLEWARE_DECIMALS;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getLowLatencyDelay() external view returns (uint16 delay_) {
        return _lowLatencyDelay;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function validationCost(bytes calldata data, Types.ProtocolAction) public view virtual returns (uint256 result_) {
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

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStream
    function setValidationDelay(uint256 newValidationDelay) external onlyRole(ADMIN_ROLE) {
        _validationDelay = newValidationDelay;

        emit ValidationDelayUpdated(newValidationDelay);
    }

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStream
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external onlyRole(ADMIN_ROLE) {
        _timeElapsedLimit = newTimeElapsedLimit;

        emit TimeElapsedLimitUpdated(newTimeElapsedLimit);
    }

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStream
    function setPythRecentPriceDelay(uint64 newDelay) external onlyRole(ADMIN_ROLE) {
        if (newDelay < 10 seconds) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        if (newDelay > 10 minutes) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        _pythRecentPriceDelay = newDelay;

        emit PythRecentPriceDelayUpdated(newDelay);
    }

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStream
    function setDataStreamRecentPriceDelay(uint64 newDelay) external onlyRole(ADMIN_ROLE) {
        if (newDelay < 10 seconds) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        if (newDelay > 10 minutes) {
            revert OracleMiddlewareInvalidRecentPriceDelay(newDelay);
        }
        _pythRecentPriceDelay = newDelay;

        emit DataStreamRecentPriceDelayUpdated(newDelay);
    }

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStream
    function setLowLatencyDelay(uint16 newLowLatencyDelay, IUsdnProtocol usdnProtocol) external onlyRole(ADMIN_ROLE) {
        if (newLowLatencyDelay > 90 minutes) {
            revert OracleMiddlewareInvalidLowLatencyDelay();
        }
        if (newLowLatencyDelay < usdnProtocol.getLowLatencyValidatorDeadline()) {
            revert OracleMiddlewareInvalidLowLatencyDelay();
        }
        _lowLatencyDelay = newLowLatencyDelay;

        emit LowLatencyDelayUpdated(newLowLatencyDelay);
    }

    /// @inheritdoc IOracleMiddlewareWithChainlinkDataStream
    function withdrawEther(address to) external onlyRole(ADMIN_ROLE) {
        if (to == address(0)) {
            revert OracleMiddlewareTransferToZeroAddress();
        }
        (bool success,) = payable(to).call{ value: address(this).balance }("");
        if (!success) {
            revert OracleMiddlewareTransferFailed(to);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the price from the low-latency oracle (Pyth).
     * @param data The signed price update data.
     * @param dir The direction of the price.
     * @return price_ The price from the low-latency oracle, adjusted according to the confidence interval direction.
     */
    function _getLiquidationPrice(bytes calldata data, ConfidenceInterval dir)
        internal
        virtual
        returns (PriceInfo memory price_)
    {
        if (_isPythData(data)) {
            FormattedPythPrice memory pythPrice = _getFormattedPythPrice(data, 0, MIDDLEWARE_DECIMALS, 0);
            return _adjustPythPrice(pythPrice);
        }

        IVerifierProxy.ReportV3 memory verifiedReport = _getChainlinkDataStreamPrice(data, 0);
        price_ = _adjustDataStreamPrice(verifiedReport, dir);
    }

    /**
     * @notice Gets the price for an `initiate` action of the protocol.
     * @dev If the data parameter is not empty, validate the price with {PythOracle}. Else, get the on-chain price from
     * {ChainlinkOracle} and compare its timestamp with the latest seen Pyth price (cached). If Pyth is more recent, we
     * return it. Otherwise, we return the Chainlink price. For the latter, we don't have a confidence interval, so both
     * `neutralPrice` and `price` are equal.
     * @param data An optional VAA from Pyth.
     * @param dir The direction when applying the confidence interval (when using a Pyth price).
     * @return price_ The price to use for the user action.
     */
    function _getInitiateActionPrice(bytes calldata data, ConfidenceInterval dir)
        internal
        returns (PriceInfo memory price_)
    {
        // if data is not empty, use pyth
        if (data.length > 0) {
            // since we use this function for `initiate` type actions which pass `targetTimestamp = block.timestamp`,
            // we should pass `0` to the function below to signal that we accept any recent price
            return _getLowLatencyPrice(data, 0, dir);
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
            return _adjustPythPrice(latestPythPrice);
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
     * @notice Converts a formatted Pyth price into a PriceInfo.
     * @param pythPrice The formatted Pyth price containing the price and publish time.
     * @return price_ The PriceInfo with the price, neutral price, and timestamp set from the Pyth price data.
     */
    function _adjustPythPrice(FormattedPythPrice memory pythPrice) internal pure returns (PriceInfo memory price_) {
        price_ = PriceInfo({ price: pythPrice.price, neutralPrice: pythPrice.price, timestamp: pythPrice.publishTime });
    }

    /**
     * @notice Applies the ask or bid according to the `dir` direction.
     * @param report The Chainlink data streams report.
     * @param dir The direction of the confidence interval to apply.
     * @return price_ The adjusted price according to the direction.
     */
    function _adjustDataStreamPrice(IVerifierProxy.ReportV3 memory report, ConfidenceInterval dir)
        internal
        pure
        returns (PriceInfo memory price_)
    {
        if (dir == ConfidenceInterval.Down) {
            price_.price = uint192(report.bid);
        } else if (dir == ConfidenceInterval.Up) {
            price_.price = uint192(report.ask);
        } else {
            price_.price = uint192(report.price);
        }

        price_.timestamp = report.observationsTimestamp;
        price_.neutralPrice = uint192(report.price);
    }

    /**
     * @notice Gets the price from the Chainlink data streams oracle.
     * @param payload The payload (full report) coming from the Chainlink data streams API.
     * @param actionTimestamp The timestamp of the action corresponding to the price. If zero, then we must accept all
     * prices younger than {ChainlinkDataStreamOracle._dataStreamRecentPriceDelay}.
     * @param dir The direction for the confidence interval adjusted price.
     * @return price_ The price from the Chainlink low-latency oracle, adjusted according to the confidence interval
     * direction.
     */
    function _getLowLatencyPrice(bytes calldata payload, uint128 actionTimestamp, ConfidenceInterval dir)
        internal
        virtual
        returns (PriceInfo memory price_)
    {
        // if actionTimestamp is 0 we're performing a liquidation or a initiate
        // action and we don't add the validation delay
        if (actionTimestamp > 0) {
            // add the validation delay to the action timestamp to get
            // the timestamp of the price data used to validate
            actionTimestamp += uint128(_validationDelay);
        }

        IVerifierProxy.ReportV3 memory verifiedReport = _getChainlinkDataStreamPrice(payload, actionTimestamp);
        price_ = _adjustDataStreamPrice(verifiedReport, dir);
    }

    /**
     * @notice Gets the price for a validate action of the protocol.
     * @dev If the low latency delay is not exceeded, validate the price with the low-latency oracle(s).
     * Else, get the specified roundId on-chain price from Chainlink. In case of Chainlink price,
     * we don't have a confidence interval and so both `neutralPrice` and `price` are equal.
     * @param data An optional VAA from Pyth or a Chainlink roundId (abi-encoded uint80).
     * @param targetTimestamp The timestamp of the initiate action.
     * @param dir The price direction to take.
     * @return price_ The price to use for the user action.
     */
    function _getValidateActionPrice(bytes calldata data, uint128 targetTimestamp, ConfidenceInterval dir)
        internal
        returns (PriceInfo memory price_)
    {
        uint128 targetLimit = targetTimestamp + _lowLatencyDelay;
        if (block.timestamp <= targetLimit) {
            return _getLowLatencyPrice(data, targetTimestamp, dir);
        }

        // Chainlink calls do not require a fee
        if (msg.value > 0) {
            revert OracleMiddlewareIncorrectFee();
        }

        uint80 validateRoundId = abi.decode(data, (uint80));

        // check that the round ID is valid and get its price data
        ChainlinkPriceInfo memory chainlinkOnChainPrice = _validateChainlinkRoundId(targetLimit, validateRoundId);

        price_ = PriceInfo({
            price: uint256(chainlinkOnChainPrice.price),
            neutralPrice: uint256(chainlinkOnChainPrice.price),
            timestamp: chainlinkOnChainPrice.timestamp
        });
    }

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
    function _isPythData(bytes calldata data) internal pure returns (bool isPythData_) {
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
