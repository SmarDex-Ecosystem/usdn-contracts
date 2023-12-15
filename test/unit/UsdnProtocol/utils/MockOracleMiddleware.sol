// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IOracleMiddleware, ProtocolAction, PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

contract MockOracleMiddleware is IOracleMiddleware {
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction, bytes calldata data)
        external
        payable
        returns (PriceInfo memory)
    {
        // TODO: return different timestamp depending on action?
        uint128 priceValue = abi.decode(data, (uint128));
        uint128 ts = targetTimestamp;
        if (ts >= 12) {
            ts = ts - 12;
        } else {
            ts = 0;
        }
        PriceInfo memory price = PriceInfo({ price: priceValue, timestamp: ts });
        return price;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function validationCost(ProtocolAction) external pure returns (uint256) {
        return 1;
    }
}
