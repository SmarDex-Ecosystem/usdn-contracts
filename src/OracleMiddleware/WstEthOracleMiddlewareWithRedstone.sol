// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IWstETH } from "../interfaces/IWstETH.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { OracleMiddleware } from "./OracleMiddleware.sol";
import { OracleMiddlewareWithRedstone } from "./OracleMiddlewareWithRedstone.sol";

/**
 * @title Contract to apply and return wsteth price
 * @notice This contract is used to get the price of wsteth from the eth price oracle
 */
contract WstEthOracleMiddlewareWithRedstone is OracleMiddlewareWithRedstone {
    /// @notice wsteth instance
    IWstETH internal immutable _wstEth;

    /**
     * @param pythContract The address of the Pyth contract
     * @param pythPriceID The ID of the Pyth price feed
     * @param redstoneFeedId The ID of the Redstone price feed
     * @param chainlinkPriceFeed The address of the Chainlink price feed
     * @param wstETH The address of the wstETH contract
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale
     */
    constructor(
        address pythContract,
        bytes32 pythPriceID,
        bytes32 redstoneFeedId,
        address chainlinkPriceFeed,
        address wstETH,
        uint256 chainlinkTimeElapsedLimit
    )
        OracleMiddlewareWithRedstone(
            pythContract,
            pythPriceID,
            redstoneFeedId,
            chainlinkPriceFeed,
            chainlinkTimeElapsedLimit
        )
    {
        _wstEth = IWstETH(wstETH);
    }

    /**
     * @inheritdoc IBaseOracleMiddleware
     * @notice Parses and validates price data by applying eth/wsteth ratio
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata
     * Wsteth price is calculated as follows: ethPrice x stEthPerToken / 1 ether
     */
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) public payable virtual override(IBaseOracleMiddleware, OracleMiddleware) returns (PriceInfo memory) {
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
