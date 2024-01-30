// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract MockOracleMiddleware is IOracleMiddleware {
    uint8 constant DECIMALS = 18;
    uint256 constant VALIDATION_DELAY = 24 seconds;

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
    function validationDelay() external pure returns (uint256) {
        return VALIDATION_DELAY;
    }

    /// @inheritdoc IOracleMiddleware
    function validationCost(bytes calldata, ProtocolAction) external pure returns (uint256) {
        return 1;
    }
}
