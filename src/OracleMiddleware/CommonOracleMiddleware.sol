// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { ICommonOracleMiddleware } from "../interfaces/OracleMiddleware/ICommonOracleMiddleware.sol";
import {
    ChainlinkPriceInfo,
    ConfidenceInterval,
    FormattedPythPrice,
    PriceInfo
} from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ChainlinkOracle } from "./oracles/ChainlinkOracle.sol";
import { PythOracle } from "./oracles/PythOracle.sol";

/**
 * @title Common Middleware Contract
 * @notice This contract serves as a common base that must be implemented by other middleware contracts.
 */
abstract contract CommonOracleMiddleware is
    ICommonOracleMiddleware,
    AccessControlDefaultAdminRules,
    ChainlinkOracle,
    PythOracle
{
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANT                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ICommonOracleMiddleware
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice The number of decimals for the returned price.
    uint8 internal constant MIDDLEWARE_DECIMALS = 18;

    /* -------------------------------------------------------------------------- */
    /*                                   Params                                   */
    /* -------------------------------------------------------------------------- */

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
        AccessControlDefaultAdminRules(0, msg.sender)
    {
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IBaseOracleMiddleware
    function getDecimals() external pure returns (uint8 decimals_) {
        return MIDDLEWARE_DECIMALS;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getValidationDelay() external view returns (uint256 delay_) {
        return _validationDelay;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getLowLatencyDelay() external view returns (uint16 delay_) {
        return _lowLatencyDelay;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function validationCost(bytes calldata data, Types.ProtocolAction) public view virtual returns (uint256 result_) {
        if (_isPythData(data)) {
            result_ = _getPythUpdateFee(data);
        }
    }

    /// @inheritdoc IBaseOracleMiddleware
    function parseAndValidatePrice(bytes32, uint128 targetTimestamp, Types.ProtocolAction action, bytes calldata data)
        public
        payable
        virtual
        returns (PriceInfo memory price_)
    {
        if (action == Types.ProtocolAction.None) {
            return
                _getLowLatencyPrice(data, targetTimestamp, ConfidenceInterval.None, targetTimestamp + _lowLatencyDelay);
        } else if (action == Types.ProtocolAction.Initialize) {
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.ValidateDeposit) {
            // use the lowest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies until low latency delay is exceeded then use chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Down);
        } else if (action == Types.ProtocolAction.ValidateWithdrawal) {
            // use the highest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies until low latency delay is exceeded then use chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Up);
        } else if (action == Types.ProtocolAction.ValidateOpenPosition) {
            // use the highest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies until low latency delay is exceeded then use chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Up);
        } else if (action == Types.ProtocolAction.ValidateClosePosition) {
            // use the lowest price in the confidence interval to ensure a minimum benefit for the user in case
            // of price inaccuracies until low latency delay is exceeded then use chainlink specified roundId
            return _getValidateActionPrice(data, targetTimestamp, ConfidenceInterval.Down);
        } else if (action == Types.ProtocolAction.Liquidation) {
            // use the neutral price from the low-latency oracle
            return _getLiquidationPrice(data);
        } else if (action == Types.ProtocolAction.InitiateDeposit) {
            // if the user chooses to initiate with pyth, the neutral price will be used so no confidence is needed
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.InitiateWithdrawal) {
            // if the user chooses to initiate with pyth, the neutral price will be used so no confidence is needed
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.InitiateOpenPosition) {
            // if the user chooses to initiate with pyth, the neutral price will be used so no confidence is needed
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        } else if (action == Types.ProtocolAction.InitiateClosePosition) {
            // if the user chooses to initiate with pyth, the neutral price will be used so no confidence is needed
            return _getInitiateActionPrice(data, ConfidenceInterval.None);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ICommonOracleMiddleware
    function setValidationDelay(uint256 newValidationDelay) external onlyRole(ADMIN_ROLE) {
        _validationDelay = newValidationDelay;

        emit ValidationDelayUpdated(newValidationDelay);
    }

    /// @inheritdoc ICommonOracleMiddleware
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external onlyRole(ADMIN_ROLE) {
        _timeElapsedLimit = newTimeElapsedLimit;

        emit TimeElapsedLimitUpdated(newTimeElapsedLimit);
    }

    /// @inheritdoc ICommonOracleMiddleware
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

    /// @inheritdoc ICommonOracleMiddleware
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

    /// @inheritdoc ICommonOracleMiddleware
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
     * @notice Gets the price from the low-latency oracle.
     * @param data The signed price update data.
     * @param actionTimestamp The timestamp of the action corresponding to the price. If zero, then we must accept all
     * prices younger than the recent price delay.
     * @param dir The direction for the confidence interval adjusted price.
     * @param targetLimit The most recent timestamp a price can have (can be zero if `actionTimestamp` is zero).
     * @return price_ The price from the low-latency oracle, adjusted according to the confidence interval direction.
     */
    function _getLowLatencyPrice(
        bytes calldata data,
        uint128 actionTimestamp,
        ConfidenceInterval dir,
        uint128 targetLimit
    ) internal virtual returns (PriceInfo memory price_);

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
        virtual
        returns (PriceInfo memory price_);

    /**
     * @notice Gets the price for a validate action of the protocol.
     * @dev If the low latency delay is not exceeded, validate the price with the low-latency oracle(s).
     * Else, get the specified roundId on-chain price from Chainlink. In case of chainlink price,
     * we don't have a confidence interval and so both `neutralPrice` and `price` are equal.
     * @param data An optional low-latency price update or a chainlink roundId (abi-encoded uint80).
     * @param targetTimestamp The timestamp of the initiate action.
     * @param dir The direction for applying the confidence interval (in case we use a low-latency price).
     * @return price_ The price to use for the user action.
     */
    function _getValidateActionPrice(bytes calldata data, uint128 targetTimestamp, ConfidenceInterval dir)
        internal
        virtual
        returns (PriceInfo memory price_)
    {
        uint128 targetLimit = targetTimestamp + _lowLatencyDelay;
        if (block.timestamp <= targetLimit) {
            return _getLowLatencyPrice(data, targetTimestamp, dir, targetLimit);
        }

        // chainlink calls do not require a fee
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
     * @notice Gets the price from the low-latency oracle.
     * @param data The signed price update data.
     * @return price_ The low-latency oracle price.
     */
    function _getLiquidationPrice(bytes calldata data) internal virtual returns (PriceInfo memory price_) {
        return _getLowLatencyPrice(data, 0, ConfidenceInterval.None, 0);
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
