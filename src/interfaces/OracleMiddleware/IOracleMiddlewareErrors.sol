// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IOracleMiddlewareErrors
 * @notice Errors for the oracle middleware
 */
interface IOracleMiddlewareErrors {
    /// @notice The oracle price is invalid (negative)
    error OracleMiddlewareWrongPrice(int256 price);

    /// @notice The oracle price is invalid (too old)
    error OracleMiddlewarePriceTooOld(int256 price, uint256 timestamp);

    /// @notice The sender could not accept the ether refund
    error OracleMiddlewareEtherRefundFailed();
}
