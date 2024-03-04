// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import {
    IOracleMiddleware,
    ProtocolAction,
    PriceInfo,
    IOracleMiddlewareErrors
} from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";

contract MockOracleMiddleware is IOracleMiddleware, Ownable {
    uint8 internal constant DECIMALS = 18;
    uint256 internal constant VALIDATION_DELAY = 24 seconds;
    uint16 private constant CONF_RATIO_DENOM = 10_000;
    uint16 private constant MAX_CONF_RATIO = CONF_RATIO_DENOM * 2;
    uint16 private _confRatio = 4000; // to divide by CONF_RATIO_DENOM
    uint256 internal _validationDelay = 24 seconds;
    uint256 internal _timeElapsedLimit = 1 hours;
    // if true, then the middleware requires a payment of 1 wei for any action
    bool internal _requireValidationCost = false;

    constructor() Ownable(msg.sender) { }

    /// @inheritdoc IOracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory)
    {
        uint128 priceValue = abi.decode(data, (uint128));
        uint128 ts = targetTimestamp;
        if (
            action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
                || action == ProtocolAction.Initialize
        ) {
            if (ts < 30 minutes) {
                // avoid underflow
                ts = 0;
            } else {
                ts -= 30 minutes; // simulate that we got the price 30 minutes ago
            }
        } else if (action == ProtocolAction.Liquidation) {
            if (ts < 30 seconds) {
                // avoid underflow
                ts = 0;
            } else {
                ts -= 30 seconds; // for liquidation, simulate we got a recent timestamp
            }
        } else {
            // for other actions, simulate we got the price from 24s after the initiate action
            ts += uint128(VALIDATION_DELAY);
        }

        PriceInfo memory price = PriceInfo({ price: priceValue, neutralPrice: priceValue, timestamp: uint48(ts) });
        return price;
    }

    /// @inheritdoc IOracleMiddleware
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc IOracleMiddleware
    function validationDelay() external pure returns (uint256) {
        return VALIDATION_DELAY;
    }

    /// @inheritdoc IOracleMiddleware
    function validationCost(bytes calldata, ProtocolAction) external view returns (uint256) {
        return _requireValidationCost ? 1 : 0;
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
    function updateValidationDelay(uint256 newDelay) external onlyOwner {
        _validationDelay = newDelay;
    }

    /// @inheritdoc IOracleMiddleware
    function setConfRatio(uint16 newConfRatio) external onlyOwner {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert IOracleMiddlewareErrors.OracleMiddlewareConfRatioTooHigh();
        }
        _confRatio = newConfRatio;
    }

    function getChainlinkTimeElapsedLimit() external view returns (uint256) {
        return _timeElapsedLimit;
    }

    /// @inheritdoc IOracleMiddleware
    function updateChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external {
        _timeElapsedLimit = newTimeElapsedLimit;
    }

    function requireValidationCost() external view returns (bool) {
        return _requireValidationCost;
    }

    function setRequireValidationCost(bool req) external {
        _requireValidationCost = req;
    }
}
