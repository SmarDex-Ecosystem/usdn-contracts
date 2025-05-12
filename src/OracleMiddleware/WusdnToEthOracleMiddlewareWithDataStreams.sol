// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { CommonOracleMiddleware, OracleMiddlewareWithDataStreams } from "./OracleMiddlewareWithDataStreams.sol";

/**
 * @title Middleware Implementation For Short ETH Protocol
 * @notice This contract is used to get the "inverse" price in ETH/WUSDN denomination, so that it can be used for a
 * shorting version of the USDN protocol with WUSDN as the underlying asset.
 * @dev This version uses Pyth or Chainlink Data Streams for liquidations, and only Chainlink Data Streams for
 * validation actions.
 */
contract WusdnToEthOracleMiddlewareWithDataStreams is OracleMiddlewareWithDataStreams {
    /// @dev One dollar with the middleware decimals.
    uint256 internal constant ONE_DOLLAR = 10 ** MIDDLEWARE_DECIMALS;

    /// @dev Max divisor from the USDN token (as constant for gas optimisation).
    uint256 internal constant USDN_MAX_DIVISOR = 1e18;

    /// @dev Numerator for the price calculation in {WusdnToEthOracleMiddlewareWithPyth.parseAndValidatePrice}.
    uint256 internal constant PRICE_NUMERATOR = 10 ** MIDDLEWARE_DECIMALS * ONE_DOLLAR * USDN_MAX_DIVISOR;

    /// @notice The USDN token address.
    IUsdn internal immutable USDN;

    /**
     * @param pythContract The address of the Pyth contract.
     * @param pythPriceID The ID of the ETH Pyth price feed.
     * @param chainlinkPriceFeed The address of the ETH Chainlink price feed.
     * @param usdnToken The address of the USDN token.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     * @param chainlinkProxyVerifierAddress The address of the Chainlink proxy verifier contract.
     * @param chainlinkStreamId The Chainlink data stream ID for ETH/USD.
     */
    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        address usdnToken,
        uint256 chainlinkTimeElapsedLimit,
        address chainlinkProxyVerifierAddress,
        bytes32 chainlinkStreamId
    )
        OracleMiddlewareWithDataStreams(
            pythContract,
            pythPriceID,
            chainlinkPriceFeed,
            chainlinkTimeElapsedLimit,
            chainlinkProxyVerifierAddress,
            chainlinkStreamId
        )
    {
        USDN = IUsdn(usdnToken);
    }

    /**
     * @inheritdoc IBaseOracleMiddleware
     * @dev This function returns an approximation of the price, so how much ETH each WUSDN token is worth.
     * The exact formula would be to divide the $/WUSDN price by the $/ETH price, which would look like this (as a
     * decimal number):
     * p = pWUSDN / pETH = (pUSDN * MAX_DIVISOR / divisor) / pETH = (pUSDN * MAX_DIVISOR) / (pETH * divisor)
     *   = ((usdnVaultBalance * pWstETH / usdnTotalSupply) * MAX_DIVISOR) / (pETH * divisor)
     *   = (usdnVaultBalance * pETH * stETHRatio * MAX_DIVISOR) / (pETH * divisor * usdnTotalSupply)
     *   = (usdnVaultBalance * stETHRatio * MAX_DIVISOR) / (usdnTotalSupply * divisor)
     *
     * Because we don't have historical access to the vault balance, the stETH ratio, the USDN total supply and the
     * USDN divisor, we must approximate some parameters. The following approximations are made:
     * - The USDN price is $1
     * - The USDN divisor's current value is valid (constant) for the period where we need to provide prices.
     *
     * This greatly simplifies the formula (with $1 and pETH having 18 decimals):
     * p = ($1 * MAX_DIVISOR) / (pETH * divisor) = 1e18 * MAX_DIVISOR / (pETH * divisor)
     *
     * Since we want to represent this price as an integer with a fixed precision of 18 decimals, the number needs
     * to be multiplied by 1e18.
     *
     * p_wei = 1e54 / (pETH * divisor)
     *
     * Because we re-use the logic of the {OracleMiddleware}, we need to invert the adjustment direction. So if an
     * action in the original protocol requires that we add the confidence interval to the neutral price (e.g. to open
     * a new long position), then this oracle middleware needs to subtract the same confidence interval from the
     * neutral price to achieve the same effect, i.e. penalizing the user. This is because the ETH price is in the
     * denominator of the formula.
     * @param actionId A unique identifier for the current action. This identifier can be used to link an `Initiate`
     * call with the corresponding `Validate` call.
     * @param targetTimestamp The target timestamp for validating the price data. For validation actions, this is the
     * timestamp of the initiation.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data The data to be used to communicate with oracles, the format varies from middleware to middleware and
     * can be different depending on the action.
     * @return result_ The price and timestamp as {IOracleMiddlewareTypes.PriceInfo}.
     */
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) public payable virtual override(CommonOracleMiddleware, IBaseOracleMiddleware) returns (PriceInfo memory) {
        PriceInfo memory ethPrice = super.parseAndValidatePrice(actionId, targetTimestamp, action, data);
        uint256 divisor = USDN.divisor();
        int256 adjustmentDelta = int256(ethPrice.price) - int256(ethPrice.neutralPrice);
        // invert the sign of the confidence interval if necessary
        if (adjustmentDelta != 0) {
            uint256 adjustedPrice;
            if (adjustmentDelta >= int256(ethPrice.neutralPrice)) {
                // avoid underflow or zero price due to confidence interval adjustment
                adjustedPrice = 1;
            } else {
                adjustedPrice = uint256(int256(ethPrice.neutralPrice) - adjustmentDelta);
            }
            return PriceInfo({
                price: PRICE_NUMERATOR / (adjustedPrice * divisor),
                neutralPrice: PRICE_NUMERATOR / (ethPrice.neutralPrice * divisor),
                timestamp: ethPrice.timestamp
            });
        } else {
            // gas optimization, only compute the price once because there is no confidence interval to apply
            uint256 price = PRICE_NUMERATOR / (ethPrice.price * divisor);
            return PriceInfo({ price: price, neutralPrice: price, timestamp: ethPrice.timestamp });
        }
    }
}
