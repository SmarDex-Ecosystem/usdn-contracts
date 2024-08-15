// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
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
contract OracleMiddleware is IOracleMiddleware, PythOracle, ChainlinkOracle, Ownable2Step, Pausable {
    /// @inheritdoc IOracleMiddleware
    uint16 public constant BPS_DIVISOR = 10_000;

    /// @inheritdoc IOracleMiddleware
    uint16 public constant MAX_CONF_RATIO = BPS_DIVISOR * 2;

    /// @notice The number of decimals for the returned price
    uint8 internal constant MIDDLEWARE_DECIMALS = 18;

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
        Ownable(msg.sender)
    { }

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
     * @param targetTimestamp The target timestamp
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

        // previous round id
        ChainlinkPriceInfo memory chainlinkOnChainPrice =
            _getFormattedChainlinkPrice(MIDDLEWARE_DECIMALS, validateRoundId - 1);

        // if the price is negative or zero, revert
        if (chainlinkOnChainPrice.price <= 0) {
            revert OracleMiddlewareWrongPrice(chainlinkOnChainPrice.price);
        }

        // if previous price is higher than targetLimit
        if (chainlinkOnChainPrice.timestamp > targetLimit) {
            revert OracleMiddlewareInvalidRoundId();
        }

        // validate round id
        chainlinkOnChainPrice = _getFormattedChainlinkPrice(MIDDLEWARE_DECIMALS, validateRoundId);

        // if the price is negative or zero, revert
        if (chainlinkOnChainPrice.price <= 0) {
            revert OracleMiddlewareWrongPrice(chainlinkOnChainPrice.price);
        }

        // if validate price is lower or equal than targetLimit
        if (chainlinkOnChainPrice.timestamp <= targetLimit) {
            revert OracleMiddlewareInvalidRoundId();
        }
        price_ = PriceInfo({
            price: uint256(chainlinkOnChainPrice.price),
            neutralPrice: uint256(chainlinkOnChainPrice.price),
            timestamp: chainlinkOnChainPrice.timestamp
        });
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
    function setPythRecentPriceDelay(uint64 newDelay) external onlyOwner {
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
    function setConfRatio(uint16 newConfRatio) external onlyOwner {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert OracleMiddlewareConfRatioTooHigh();
        }

        _confRatioBps = newConfRatio;

        emit ConfRatioUpdated(newConfRatio);
    }

    /// @inheritdoc IOracleMiddleware
    function setLowLatencyDelay(uint16 newLowLatencyDelay) external onlyOwner {
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
    function withdrawEther(address to) external onlyOwner {
        if (to == address(0)) {
            revert OracleMiddlewareTransferToZeroAddress();
        }

        (bool success,) = payable(to).call{ value: address(this).balance }("");
        if (!success) {
            revert OracleMiddlewareTransferFailed(to);
        }
    }

    /// @inheritdoc IOracleMiddleware
    function pausePriceValidation() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IOracleMiddleware
    function unpausePriceValidation() external onlyOwner {
        _unpause();
    }
}
