// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface IOracleMiddleware {
    /**
     * @notice Parses and validates price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * @param targetTimestamp The timestamp for which the price is requested. The middleware may use this to validate
     * whether the price is fresh enough.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the returned
     * price.
     * @param data Price data, the format varies from middleware to middleware.
     * @return PriceInfo The price and timestamp.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory);

    function decimals() external view returns (uint8);
}

/* -------------------------------------------------------------------------- */
/*                     Oracle middleware struct and enums                     */
/* -------------------------------------------------------------------------- */

/// @notice The price and timestamp returned by the oracle middleware.
/// @dev The timestamp is the timestamp of the price data, not the timestamp of the request.
/// @param price The current asset price.
/// @param timestamp The timestamp of the price data.
struct PriceInfo {
    uint128 price;
    uint128 timestamp;
}

/// @notice The type of action for which the price is requested.
/// @dev The middleware may use this to alter the returned price.
/// @param None No particular action.
/// @param Deposit The price is requested for a deposit action.
/// @param Withdraw The price is requested for a withdraw action.
/// @param OpenPosition The price is requested for an open position action.
/// @param ClosePosition The price is requested for a close position action.
/// @param LiquidatePosition The price is requested for a liquidate position action.
enum ProtocolAction {
    None,
    Deposit,
    Withdraw,
    ValidateWithdraw,
    OpenPosition,
    ValidateOpenPosition,
    ClosePosition,
    ValidateClosePosition,
    LiquidatePosition
}
