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
    uint16 public constant BPS_DIVISOR = 10_000;
    uint16 public constant MAX_CONF_RATIO = BPS_DIVISOR * 2;
    uint8 internal constant DECIMALS = 18;

    uint16 internal _confRatioBps = 4000;
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
        require(block.timestamp >= 30 minutes, "MockOracleMiddleware: set block timestamp before calling");
        uint256 priceValue = abi.decode(data, (uint128));
        uint256 ts;
        if (
            action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
                || action == ProtocolAction.Initialize
        ) {
            // simulate that we got the price 30 minutes ago
            ts = block.timestamp - 30 minutes;
        } else if (action == ProtocolAction.Liquidation) {
            // for liquidation, simulate we got a recent timestamp
            ts = block.timestamp - 30 seconds;
        } else {
            // for other actions, simulate we got the price from 24s after the initiate action
            ts = targetTimestamp + _validationDelay;
        }
        // the timestamp cannot be in the future (the caller must `skip` before calling this function)
        require(ts < block.timestamp, "MockOracleMiddleware: timestamp is in the future");

        PriceInfo memory price = PriceInfo({ price: priceValue, neutralPrice: priceValue, timestamp: ts });
        return price;
    }

    /// @inheritdoc IOracleMiddleware
    function getDecimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc IOracleMiddleware
    function getValidationDelay() external view returns (uint256) {
        return _validationDelay;
    }

    /// @inheritdoc IOracleMiddleware
    function validationCost(bytes calldata, ProtocolAction) external view returns (uint256) {
        return _requireValidationCost ? 1 : 0;
    }

    /// @inheritdoc IOracleMiddleware
    function getConfRatioBps() external view returns (uint16) {
        return _confRatioBps;
    }

    /// @inheritdoc IOracleMiddleware
    function setValidationDelay(uint256 newDelay) external {
        _validationDelay = newDelay;
    }

    /// @inheritdoc IOracleMiddleware
    function setConfRatio(uint16 newConfRatio) external onlyOwner {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert IOracleMiddlewareErrors.OracleMiddlewareConfRatioTooHigh();
        }
        _confRatioBps = newConfRatio;
    }

    /// @inheritdoc IOracleMiddleware
    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external {
        _timeElapsedLimit = newTimeElapsedLimit;
    }

    function setRecentPriceDelay(uint64) external {
        // Do something if needed
    }

    function requireValidationCost() external view returns (bool) {
        return _requireValidationCost;
    }

    function setRequireValidationCost(bool req) external {
        _requireValidationCost = req;
    }

    function withdrawEther(address to) external {
        (bool success,) = payable(to).call{ value: address(this).balance }("");
        if (!success) {
            revert OracleMiddlewareTransferFailed(to);
        }
    }
}
