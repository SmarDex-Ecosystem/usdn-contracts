// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IOracleMiddleware, PriceInfo } from "../interfaces/IOracleMiddleware.sol";
import { ProtocolAction } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract OracleMiddleware is IOracleMiddleware {
    /**
     * @notice Parses and validates price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * @param targetTimestamp The timestamp for which the price is requested. The middleware may use this to validate
     * whether the price is fresh enough.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data Price data, the format varies from middleware to middleware and can be different depending on the
     * action.
     * @return The price and timestamp as `PriceInfo`.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory)
    { }

    /// @notice Returns the number of decimals for the price (constant)
    function decimals() external view returns (uint8) { }

    /// @notice Returns the ETH cost of one price validation for the given action
    function validationCost(ProtocolAction action) external returns (uint256) { }
}
