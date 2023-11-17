// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { IOracleMiddleware, ProtocolAction, PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

error MissingFee();

/**
 * @title OracleMiddleware
 * @dev Oracle middleware
 */
contract OracleMiddleware is IOracleMiddleware {
    constructor() { }

    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory price)
    {
        if (msg.value == 0) {
            revert MissingFee();
        }
        uint128 _inputPrice = abi.decode(data, (uint128));

        price.timestamp = targetTimestamp + 2;
        price.price = _inputPrice;
    }

    function decimals() external view returns (uint8) {
        return uint8(18);
    }
}
