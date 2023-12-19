// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IOracleMiddleware, ProtocolAction, PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

contract MockOracleMiddleware is IOracleMiddleware {
    /// @inheritdoc IOracleMiddleware
    uint256 public constant validationDelay = 24 seconds;

    /// @inheritdoc IOracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction, bytes calldata data)
        external
        payable
        returns (PriceInfo memory)
    {
        // TODO: return different timestamp depending on action?
        uint128 priceValue = abi.decode(data, (uint128));
        uint128 ts = targetTimestamp;
        if (ts >= validationDelay) {
            ts = ts - uint128(validationDelay); // simulate that we got the price 24 seconds ago
        } else {
            ts = 0;
        }
        PriceInfo memory price = PriceInfo({ price: priceValue, timestamp: ts });
        return price;
    }

    /// @inheritdoc IOracleMiddleware
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @inheritdoc IOracleMiddleware
    function validationCost(ProtocolAction) external pure returns (uint256) {
        return 1;
    }
}
