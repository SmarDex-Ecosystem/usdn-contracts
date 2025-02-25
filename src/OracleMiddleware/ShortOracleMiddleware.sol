// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IWstETH } from "../interfaces/IWstETH.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { OracleMiddleware } from "./OracleMiddleware.sol";

/**
 * @title Middleware Implementation For Short ETH Protocol
 * @notice This contract is used to get the "inverse" price in ETH/WUSDN denomination, so that it can be used for a
 * shorting version of the USDN protocol with WUSDN as the underlying asset.
 */
contract ShortOracleMiddleware is OracleMiddleware {
    using SafeCast for uint256;

    /// @notice The wstETH contract.
    IWstETH internal immutable WSTETH;

    /// @notice The address of the USDN protocol.
    IUsdnProtocol internal immutable USDN_PROTOCOL;

    /// @notice The USDN token address.
    IUsdn internal immutable USDN;

    /**
     * @param pythContract The address of the Pyth contract.
     * @param pythPriceID The ID of the ETH Pyth price feed.
     * @param chainlinkPriceFeed The address of the ETH Chainlink price feed.
     * @param wstETH The address of the wstETH contract.
     * @param usdnProtocol The address of the USDN protocol.
     * @param chainlinkTimeElapsedLimit The duration after which a Chainlink price is considered stale.
     */
    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        address wstETH,
        address usdnProtocol,
        uint256 chainlinkTimeElapsedLimit
    ) OracleMiddleware(pythContract, pythPriceID, chainlinkPriceFeed, chainlinkTimeElapsedLimit) {
        WSTETH = IWstETH(wstETH);
        USDN_PROTOCOL = IUsdnProtocol(usdnProtocol);
        USDN = USDN_PROTOCOL.getUsdn();
    }

    /**
     * @inheritdoc OracleMiddleware
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
    ) public payable virtual override returns (PriceInfo memory) {
        PriceInfo memory ethPrice = super.parseAndValidatePrice(actionId, targetTimestamp, action, data);
        int256 adjustmentDelta = int256(ethPrice.price) - int256(ethPrice.neutralPrice);
        uint256 adjustedPrice;
        if (adjustmentDelta > int256(ethPrice.neutralPrice)) {
            // avoid underflow or zero price due to confidence interval adjustment
            adjustedPrice = 1;
        } else {
            adjustedPrice = uint256(int256(ethPrice.neutralPrice) - adjustmentDelta);
        }
        uint256 stEthPerToken = WSTETH.stEthPerToken();
        uint128 wstEthPrice = (adjustedPrice * stEthPerToken / 1 ether).toUint128();
        uint128 wstEthNeutralPrice = (ethPrice.neutralPrice * stEthPerToken / 1 ether).toUint128();
        uint256 vaultBalance = USDN_PROTOCOL.vaultAssetAvailableWithFunding(wstEthPrice, uint128(ethPrice.timestamp));
        uint256 vaultBalanceNeutral =
            USDN_PROTOCOL.vaultAssetAvailableWithFunding(wstEthNeutralPrice, uint128(ethPrice.timestamp));
        uint256 usdnTotalSupply = USDN.totalSupply();
        uint256 divisor = USDN.divisor();

        return PriceInfo({
            price: (vaultBalance * stEthPerToken) / (usdnTotalSupply * divisor),
            neutralPrice: (vaultBalanceNeutral * stEthPerToken) / (usdnTotalSupply * divisor),
            timestamp: ethPrice.timestamp
        });
    }
}
