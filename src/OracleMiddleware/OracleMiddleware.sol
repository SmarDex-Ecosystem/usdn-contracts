// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IOracleMiddleware } from "../interfaces/OracleMiddleware/IOracleMiddleware.sol";
import {
    ChainlinkPriceInfo,
    ConfidenceInterval,
    FormattedPythPrice,
    PriceInfo
} from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ChainlinkOracle } from "./oracles/ChainlinkOracle.sol";
import { PythOracle } from "./oracles/PythOracle.sol";

/**
 * @title OracleMiddleware contract
 * @notice This contract is used to get the price of an asset from different price oracle
 * It is used by the USDN protocol to get the price of the USDN underlying asset
 * @dev This contract is a middleware between the USDN protocol and the price oracles
 */
contract OracleMiddleware is
    IOracleMiddleware,
    PythOracle,
    ChainlinkOracle,
    Pausable,
    AccessControlDefaultAdminRules
{
    /// @inheritdoc IOracleMiddleware
    uint16 public constant BPS_DIVISOR = 10_000;

    /// @inheritdoc IOracleMiddleware
    uint16 public constant MAX_CONF_RATIO = BPS_DIVISOR * 2;

    /// @notice The number of decimals for the returned price
    uint8 internal constant MIDDLEWARE_DECIMALS = 18;

    /// @inheritdoc IOracleMiddleware
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @inheritdoc IOracleMiddleware
    bytes32 public constant PAUSABLE_ROLE = keccak256("PAUSABLE_ROLE");

    /**
     * @notice The delay (in seconds) between the moment an action is initiated and the timestamp of the
     * price data used to validate that action
     */
    uint256 internal _validationDelay = 24 seconds;

    /// @notice confidence ratio in basis points: default 40%
    uint16 internal _confRatioBps = 4000; // to divide by BPS_DIVISOR

    /// @notice The delay during which a low latency oracle price validation is available
    uint16 internal _lowLatencyDelay = 20 minutes;

    /**
     * @param pythContract Address of the Pyth contract
     * @param pythFeedId The Pyth price feed ID for the asset
     * @param chainlinkPriceFeed Address of the Chainlink price feed
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale
     */
    constructor(address pythContract, bytes32 pythFeedId, address chainlinkPriceFeed, uint256 chainlinkTimeElapsedLimit)
        PythOracle(pythContract, pythFeedId)
        ChainlinkOracle(chainlinkPriceFeed, chainlinkTimeElapsedLimit)
        AccessControlDefaultAdminRules(0, msg.sender)
    {
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PAUSABLE_ROLE, msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Public view functions                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IBaseOracleMiddleware
     * @dev In the current implementation, the `actionId` value is not used
     */
    function parseAndValidatePrice(bytes32, uint128 targetTimestamp, Types.ProtocolAction action, bytes calldata data)
        public
        payable
        virtual
        whenNotPaused
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
            // special case, if we pass a timestamp of zero, then we accept all prices newer than
            // `_pythRecentPriceDelay`
            return _getLowLatencyPrice(data, 0, ConfidenceInterval.None, 0);
        } else if (action == Types.ProtocolAction.InitiateDeposit) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Down);
        } else if (action == Types.ProtocolAction.InitiateWithdrawal) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Up);
        } else if (action == Types.ProtocolAction.InitiateOpenPosition) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Up);
        } else if (action == Types.ProtocolAction.InitiateClosePosition) {
            // If the user chooses to initiate with a pyth price, we apply the relevant confidence interval adjustment
            return _getInitiateActionPrice(data, ConfidenceInterval.Down);
        }
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getValidationDelay() external view returns (uint256) {
        return _validationDelay;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getDecimals() external pure returns (uint8) {
        return MIDDLEWARE_DECIMALS;
    }

    /// @inheritdoc IOracleMiddleware
    function getConfRatioBps() external view returns (uint16) {
        return _confRatioBps;
    }

    /// @inheritdoc IOracleMiddleware
    function getLowLatencyDelay() external view returns (uint16) {
        return _lowLatencyDelay;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function validationCost(bytes calldata data, Types.ProtocolAction) public view virtual returns (uint256 result_) {
        if (_isPythData(data)) {
            result_ = _getPythUpdateFee(data);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Get the price from the low-latency oracle (Pyth)
     * @param data The signed price update data
     * @param actionTimestamp The timestamp of the action corresponding to the price. If zero, then we must accept all
     * recent prices according to `_pythRecentPriceDelay`
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
    ) internal virtual returns (PriceInfo memory price_) {
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

    /**
     * @notice Get the price for an `initiate` action of the protocol
     * @dev If the data parameter is not empty, validate the price with PythOracle. Else, get the on-chain price from
     * Chainlink and compare its timestamp with the latest seen Pyth price (cached). If Pyth is more recent, we return
     * it. Otherwise, we return the chainlink price. In the case of chainlink price, we don't have a confidence interval
     * and so both `neutralPrice` and `price` are equal
     * @param data An optional VAA from Pyth
     * @param dir The direction for applying the confidence interval (in case we use a Pyth price)
     * @return price_ The price to use for the user action
     */
    function _getInitiateActionPrice(bytes calldata data, ConfidenceInterval dir)
        internal
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
     * @notice Apply the confidence interval in the `dir` direction, scaling it by the configured `_confRatioBps`
     * @param pythPrice The formatted Pyth price object
     * @param dir The direction to apply the confidence interval
     * @return price_ The adjusted price according to the confidence interval and confidence ratio
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

    /**
     * @notice Get the price for a validate action of the protocol
     * @dev If the low latency delay is not exceeded, validate the price with the low-latency oracle(s)
     * Else, get the specified roundId on-chain price from Chainlink. In case of chainlink price,
     * we don't have a confidence interval and so both `neutralPrice` and `price` are equal
     * @param data An optional VAA from Pyth or a chainlink roundId (abi-encoded uint80)
     * @param targetTimestamp The timestamp of the initiate action
     * @param dir The direction for applying the confidence interval (in case we use a Pyth price)
     * @return price_ The price to use for the user action
     */
    function _getValidateActionPrice(bytes calldata data, uint128 targetTimestamp, ConfidenceInterval dir)
        internal
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
     * @notice Make sure that the given round ID matches with the validation constraints
     * @param targetLimit The timestamp of the initiate action + _lowLatencyDelay
     * @param roundId The round ID to validate
     * @return providedRoundPrice_ The price data of the provided round ID
     */
    function _validateChainlinkRoundId(uint128 targetLimit, uint80 roundId)
        internal
        view
        returns (ChainlinkPriceInfo memory providedRoundPrice_)
    {
        uint80 previousRoundId = roundId - 1;
        providedRoundPrice_ = _getFormattedChainlinkPrice(MIDDLEWARE_DECIMALS, roundId);

        if (providedRoundPrice_.price <= 0) {
            revert OracleMiddlewareWrongPrice(providedRoundPrice_.price);
        }

        (, int256 previousRoundPrice,, uint256 previousRoundTimestamp,) = _priceFeed.getRoundData(previousRoundId);

        if (previousRoundPrice > 0) {
            // if previous price is higher than targetLimit
            if (previousRoundTimestamp > targetLimit) {
                revert OracleMiddlewareInvalidRoundId();
            }
        } else {
            // if the provided round's price is 0, it's possible the aggregator recently changed and there is no data
            // available for the previous round ID in the aggregator. In that case, we accept the given round ID as the
            // sole reference with additional checks to make sure it is not too far from the target timestamp

            // calculate the provided round's phase ID
            uint80 roundPhaseId = roundId >> 64;
            // calculate the first valid round ID for this phase
            uint80 firstRoundId = (roundPhaseId << 64) + 1;
            // the provided round ID must be the first round ID of the phase, if not, revert
            if (firstRoundId != roundId) {
                revert OracleMiddlewareInvalidRoundId();
            }

            (uint80 latestRoundId,,,,) = _priceFeed.latestRoundData();
            // if the provided round ID does not belong to the latest phase, revert
            if (latestRoundId >> 64 != roundPhaseId) {
                revert OracleMiddlewareInvalidRoundId();
            }

            // make sure that the provided round ID is not newer than it should be
            if (providedRoundPrice_.timestamp > targetLimit + _timeElapsedLimit) {
                revert OracleMiddlewareInvalidRoundId();
            }
        }

        if (providedRoundPrice_.timestamp <= targetLimit) {
            revert OracleMiddlewareInvalidRoundId();
        }
    }

    /**
     * @notice Check if the passed calldata corresponds to a Pyth message
     * @param data The calldata pointer to the message
     * @return Whether the data is for a Pyth message
     */
    function _isPythData(bytes calldata data) internal pure returns (bool) {
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

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOracleMiddleware
    function setValidationDelay(uint256 newValidationDelay) external onlyRole(ADMIN_ROLE) {
        _validationDelay = newValidationDelay;

        emit ValidationDelayUpdated(newValidationDelay);
    }

    /// @inheritdoc IOracleMiddleware
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external onlyRole(ADMIN_ROLE) {
        _timeElapsedLimit = newTimeElapsedLimit;

        emit TimeElapsedLimitUpdated(newTimeElapsedLimit);
    }

    /// @inheritdoc IOracleMiddleware
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

    /// @inheritdoc IOracleMiddleware
    function setConfRatio(uint16 newConfRatio) external onlyRole(ADMIN_ROLE) {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert OracleMiddlewareConfRatioTooHigh();
        }

        _confRatioBps = newConfRatio;

        emit ConfRatioUpdated(newConfRatio);
    }

    /// @inheritdoc IOracleMiddleware
    function setLowLatencyDelay(uint16 newLowLatencyDelay) external onlyRole(ADMIN_ROLE) {
        if (newLowLatencyDelay < 15 minutes) {
            revert OracleMiddlewareInvalidLowLatencyDelay();
        }
        if (newLowLatencyDelay > 90 minutes) {
            revert OracleMiddlewareInvalidLowLatencyDelay();
        }
        _lowLatencyDelay = newLowLatencyDelay;

        emit LowLatencyDelayUpdated(newLowLatencyDelay);
    }

    /// @inheritdoc IOracleMiddleware
    function withdrawEther(address to) external onlyRole(ADMIN_ROLE) {
        if (to == address(0)) {
            revert OracleMiddlewareTransferToZeroAddress();
        }

        (bool success,) = payable(to).call{ value: address(this).balance }("");
        if (!success) {
            revert OracleMiddlewareTransferFailed(to);
        }
    }

    /// @inheritdoc IOracleMiddleware
    function pausePriceValidation() external onlyRole(PAUSABLE_ROLE) {
        _pause();
    }

    /// @inheritdoc IOracleMiddleware
    function unpausePriceValidation() external onlyRole(PAUSABLE_ROLE) {
        _unpause();
    }
}
