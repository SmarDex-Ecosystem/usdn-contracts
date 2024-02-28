// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";

/**
 * @title Contract to apply and return wsteth price
 * @notice This contract is used to get the price of wsteth from steth price oracle.
 */
contract WstEthOracleMiddleware is OracleMiddleware {
    /// @notice wsteth instance
    IWstETH internal immutable _wstEth;

    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        address wsteth,
        uint256 chainlinkTimeElapsedLimit
    ) OracleMiddleware(pythContract, pythPriceID, chainlinkPriceFeed, chainlinkTimeElapsedLimit) {
        _wstEth = IWstETH(wsteth);
    }

    /**
     * @notice Parses and validates price data by applying steth/wsteth ratio.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * Wsteth price is calculated as follows : stethPrice x stEthPerToken / 1 ether.
     * @param targetTimestamp The target timestamp for validating the price data. For validation actions, this is the
     * timestamp of the initiation.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data Price data, the format varies from middleware to middleware and can be different depending on the
     * action.
     * @return The price and timestamp as `PriceInfo`.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        public
        payable
        virtual
        override
        returns (PriceInfo memory)
    {
        // fetched steth price
        PriceInfo memory stethPrice = super.parseAndValidatePrice(targetTimestamp, action, data);

        // stEth ratio for one wstEth
        uint256 stEthPerToken = _wstEth.stEthPerToken();

        // wsteth price
        return PriceInfo({
            price: stethPrice.price * stEthPerToken / 1 ether,
            neutralPrice: stethPrice.neutralPrice * stEthPerToken / 1 ether,
            timestamp: stethPrice.timestamp
        });
    }
}
