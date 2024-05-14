// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";

/**
 * @title Contract to apply and return wsteth price
 * @notice This contract is used to get the price of wsteth from steth price oracle
 */
contract WstEthOracleMiddleware is OracleMiddleware {
    /// @notice wsteth instance
    IWstETH internal immutable _wstEth;

    /**
     * @param pythContract The address of the Pyth contract
     * @param pythPriceID The ID of the Pyth price feed
     * @param chainlinkPriceFeed The address of the Chainlink price feed
     * @param wstETH The address of the wstETH contract
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale
     */
    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        address wstETH,
        uint256 chainlinkTimeElapsedLimit
    ) OracleMiddleware(pythContract, pythPriceID, chainlinkPriceFeed, chainlinkTimeElapsedLimit) {
        _wstEth = IWstETH(wstETH);
    }

    /**
     * @inheritdoc OracleMiddleware
     * @notice Parses and validates price data by applying steth/wsteth ratio
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata
     * Wsteth price is calculated as follows : stethPrice x stEthPerToken / 1 ether
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
