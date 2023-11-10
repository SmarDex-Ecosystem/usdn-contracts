// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                         Oracle middleware interface                        */
/* -------------------------------------------------------------------------- */

interface IOracleMiddleware {
    /**
     * @notice Parses and validates price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * @param targetTimestamp The timestamp for which the price is requested. The middleware may use this to validate
     * whether the price is fresh enough.
     * @param direction Whether the action corresponds to a position opening (1) or position neutral (0) position
     * closing (-1). This
     * allows the middleware to use different prices for opening and closing (e.g. using the Pyth confidence interval).
     * @param data Price data, the format varies from middleware to middleware.
     * @return PriceInfo The price and timestamp.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, int8 direction, bytes calldata data)
        external
        payable
        returns (PriceInfo memory);

    function decimals() external view returns (uint8);
}

/* -------------------------------------------------------------------------- */
/*                              Price info struc                              */
/* -------------------------------------------------------------------------- */

struct PriceInfo {
    uint128 price;
    uint128 timestamp;
}
