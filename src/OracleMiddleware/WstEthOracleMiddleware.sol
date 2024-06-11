// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IWstETH } from "../interfaces/IWstETH.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { OracleMiddleware } from "../OracleMiddleware/OracleMiddleware.sol";

/**
 * @title Contract to apply and return wsteth price
 * @notice This contract is used to get the price of wsteth from the eth price oracle
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
     * @notice Parses and validates price data by applying eth/wsteth ratio
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata
     * Wsteth price is calculated as follows: ethPrice x stEthPerToken / 1 ether
     */
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        ProtocolAction action,
        bytes calldata data
    ) public payable virtual override returns (PriceInfo memory) {
        // fetched eth price
        PriceInfo memory ethPrice = super.parseAndValidatePrice(actionId, targetTimestamp, action, data);

        // stEth ratio for one wstEth
        uint256 stEthPerToken = _wstEth.stEthPerToken();

        // wsteth price
        return PriceInfo({
            price: ethPrice.price * stEthPerToken / 1 ether,
            neutralPrice: ethPrice.neutralPrice * stEthPerToken / 1 ether,
            timestamp: ethPrice.timestamp
        });
    }
}
