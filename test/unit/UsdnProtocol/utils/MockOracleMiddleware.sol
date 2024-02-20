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
    uint8 constant DECIMALS = 18;
    uint256 internal constant VALIDATION_DELAY = 24 seconds;
    uint16 private constant CONF_RATIO_DENOM = 10_000;
    uint16 private constant MAX_CONF_RATIO = CONF_RATIO_DENOM * 2;
    uint16 private _confRatio = 4000; // to divide by CONF_RATIO_DENOM

    constructor() Ownable(msg.sender) { }

    /// @inheritdoc IOracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction, bytes calldata data)
        external
        payable
        returns (PriceInfo memory)
    {
        // TODO: return different timestamp depending on action?
        uint128 priceValue = abi.decode(data, (uint128));
        uint128 ts = targetTimestamp;
        if (ts >= VALIDATION_DELAY) {
            ts = ts - uint128(VALIDATION_DELAY); // simulate that we got the price 24 seconds ago
        } else {
            ts = 0;
        }
        PriceInfo memory price = PriceInfo({ price: priceValue, neutralPrice: priceValue, timestamp: uint48(ts) });
        return price;
    }

    /// @inheritdoc IOracleMiddleware
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc IOracleMiddleware
    function validationDelay() external view returns (uint256) {
        return VALIDATION_DELAY;
    }

    /// @inheritdoc IOracleMiddleware
    function validationCost(bytes calldata, ProtocolAction) external pure returns (uint256) {
        return 1;
    }

    /// @inheritdoc IOracleMiddleware
    function maxConfRatio() external pure returns (uint16) {
        return MAX_CONF_RATIO;
    }

    /// @inheritdoc IOracleMiddleware
    function confRatioDenom() external pure returns (uint16) {
        return CONF_RATIO_DENOM;
    }

    /// @inheritdoc IOracleMiddleware
    function confRatio() external view returns (uint16) {
        return _confRatio;
    }

    /// @inheritdoc IOracleMiddleware
    function updateValidationDelay(uint256 newDelay) external onlyOwner { }

    /// @inheritdoc IOracleMiddleware
    function setConfRatio(uint16 newConfRatio) external onlyOwner {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert IOracleMiddlewareErrors.OracleMiddlewareConfRatioTooHigh();
        }
        _confRatio = newConfRatio;
    }
}
