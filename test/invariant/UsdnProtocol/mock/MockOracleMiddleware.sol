// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

import { OracleMiddleware } from "../../../../src/OracleMiddleware/OracleMiddleware.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @notice Contract to apply and return a mocked wstETH price
 * @dev This contract always returns a mocked wstETH price
 */
contract MockOracleMiddleware is OracleMiddleware {
    using EnumerableMap for EnumerableMap.UintToUintMap;

    uint256 internal constant MAX_CONF_BPS = 200; // 2% max
    uint256 internal constant VALIDATION_DELAY = 24 seconds;
    uint256 internal constant MAX_PRICE_INCREMENT = 20 ether; // $20

    EnumerableMap.UintToUintMap internal _prices; // append-only map of timestamps to prices

    constructor(uint128 initialPrice) OracleMiddleware(address(0), "", address(0), 0) {
        _prices.set(block.timestamp, initialPrice);
    }

    function updatePrice(uint256 rand) public {
        (uint256 lastTimestamp, uint256 lastPrice) = _prices.at(_prices.length() - 1);
        if (lastTimestamp == block.timestamp) {
            return;
        }
        uint256 increment = rand % MAX_PRICE_INCREMENT;
        if (rand % 2 == 0) {
            if (lastPrice + increment > type(uint128).max) {
                _prices.set(block.timestamp, type(uint128).max - increment);
            } else {
                _prices.set(block.timestamp, lastPrice + increment);
            }
        } else {
            if (lastPrice < increment) {
                _prices.set(block.timestamp, increment);
            } else {
                _prices.set(block.timestamp, lastPrice - increment);
            }
        }
    }

    /// @inheritdoc OracleMiddleware
    function parseAndValidatePrice(bytes32, uint128 targetTimestamp, Types.ProtocolAction action, bytes calldata)
        public
        payable
        override
        returns (PriceInfo memory price_)
    {
        // register a new latest price if needed (new block)
        updatePrice(uint256(keccak256(abi.encodePacked(block.number, block.timestamp))));

        // initiate actions, we want to return an on-chain price which is at least 15 minutes old
        if (
            action == Types.ProtocolAction.InitiateDeposit || action == Types.ProtocolAction.InitiateWithdrawal
                || action == Types.ProtocolAction.InitiateOpenPosition
                || action == Types.ProtocolAction.InitiateClosePosition || action == Types.ProtocolAction.Initialize
        ) {
            uint256 i = _prices.length();
            uint256 timestamp;
            uint256 price;
            do {
                i--;
                (timestamp, price) = _prices.at(i);
                if (timestamp <= block.timestamp - 15 minutes) {
                    // price is old enough, we return it
                    price_.timestamp = timestamp;
                    price_.neutralPrice = price;
                    price_.price = price;
                    return price_;
                }
            } while (i > 0);
            // we couldn't find an old enough price let's return the oldest we found
            price_.timestamp = timestamp;
            price_.neutralPrice = price;
            price_.price = price;
            return price_;
        }
        // validate actions, we need to return the first price which comes after the target timestamp + validation delay
        else if (
            action == Types.ProtocolAction.ValidateDeposit || action == Types.ProtocolAction.ValidateWithdrawal
                || action == Types.ProtocolAction.ValidateOpenPosition
                || action == Types.ProtocolAction.ValidateClosePosition
        ) {
            uint256 i = 0;
            uint256 timestamp;
            uint256 price;
            do {
                (timestamp, price) = _prices.at(i);
                if (timestamp >= targetTimestamp + VALIDATION_DELAY) {
                    // price is new enough, we return it
                    price_.timestamp = timestamp;
                    price_.neutralPrice = price;
                    price_.price = price;
                    return price_;
                }
                i++;
            } while (i < _prices.length());
            // we couldn't find a new enough price let's return the latest
            price_.timestamp = timestamp;
            price_.neutralPrice = price;
            // confidence interval
            if (
                action == Types.ProtocolAction.ValidateWithdrawal || action == Types.ProtocolAction.ValidateOpenPosition
            ) {
                price_.price = price + _priceConf(price);
            } else {
                price_.price = price - _priceConf(price);
            }
            return price_;
        }
        // liquidations, we want a recent price, ideally the one before the current block, otherwise the latest
        else if (action == Types.ProtocolAction.Liquidation) {
            uint256 at;
            if (_prices.length() > 1) {
                at = _prices.length() - 2;
            } else {
                at = _prices.length() - 1;
            }
            (uint256 timestamp, uint256 price) = _prices.at(at);
            if (timestamp < block.timestamp - 45 seconds) {
                // the one before last is too old, we return the latest
                (timestamp, price) = _prices.at(_prices.length() - 1);
            }
            price_.timestamp = timestamp;
            price_.neutralPrice = price;
            price_.price = price;
            return price_;
        }

        // none, get latest price
        (uint256 lastTimestamp, uint256 lastPrice) = _prices.at(_prices.length() - 1);
        price_.timestamp = lastTimestamp;
        price_.neutralPrice = lastPrice;
        price_.price = lastPrice;
    }

    /// @inheritdoc OracleMiddleware
    function validationCost(bytes calldata, Types.ProtocolAction action)
        public
        pure
        override
        returns (uint256 result_)
    {
        if (
            action == Types.ProtocolAction.ValidateWithdrawal || action == Types.ProtocolAction.ValidateOpenPosition
                || action == Types.ProtocolAction.ValidateDeposit || action == Types.ProtocolAction.ValidateClosePosition
                || action == Types.ProtocolAction.Liquidation || action == Types.ProtocolAction.None
        ) {
            return 1;
        }
    }

    function _priceConf(uint256 neutralPrice) internal pure returns (uint256) {
        // determine the confidence interval value for the price
        return uint256(keccak256(abi.encodePacked(neutralPrice))) % MAX_CONF_BPS;
    }
}
