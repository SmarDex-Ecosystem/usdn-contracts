// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";

/**
 * @title Contract to apply and return a mocked wsteth price
 * @notice This contract is used to get the price of wsteth
 * by setting up a price or forward to wstethMiddleware.
 * This aim to simulate price up or down. Do not use it in production.
 */
contract MockWstEthOracleMiddleware is WstEthOracleMiddleware {
    /// @notice Confidence interval denominator
    uint64 internal constant CONF_DENOM = 10_000;
    /// @notice Confidence interval percentage numerator
    uint64 internal _wstethMockedConfPct = 500; // default 5% conf
    /**
     * @notice Wsteth mocked price
     * @dev This price will be used if greater than zero.
     */
    uint256 internal _wstethMockedPrice;

    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        address wsteth,
        uint256 initialWstethMockedPrice
    ) WstEthOracleMiddleware(pythContract, pythPriceID, chainlinkPriceFeed, wsteth) {
        _wstethMockedPrice = initialWstethMockedPrice;
    }

    /**
     * @notice Parses and validates price data by returning current wsteth mocked price.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
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
        // Parse and validate from parent wsteth middleware.
        // This aim to verify pyth price hermes signature in any case.
        PriceInfo memory price = super.parseAndValidatePrice(targetTimestamp, action, data);

        // If mocked price is not set.
        if (_wstethMockedPrice == 0) {
            return price;
            // If mocked price is set.
        } else {
            // neutralPrice.
            price.neutralPrice = _wstethMockedPrice;
            // price initialized with neutralPrice.
            price.price = price.neutralPrice;

            // ConfidenceInterval Down cases
            if (
                action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition
                    || action == ProtocolAction.Liquidation
            ) {
                price.price -= price.price * _wstethMockedConfPct / CONF_DENOM;

                // ConfidenceInterval Up case
            } else if (action == ProtocolAction.ValidateOpenPosition) {
                price.price += price.price * _wstethMockedConfPct / CONF_DENOM;
            }

            return price;
        }
    }

    /**
     * @notice Set Wsteth mocked price.
     * @dev If new mocked wsteth is greater than zero this will validate this mocked price
     * else this will validate the parent middleware price.
     * @param newWstethMockedPrice .
     */
    function setWstethMockedPrice(uint256 newWstethMockedPrice) external {
        _wstethMockedPrice = newWstethMockedPrice;
    }

    /**
     * @notice Set Wsteth mocked confidence interval percentage.
     * @dev To calculate a percentage of neutral price up or down in some protocol actions.
     * @param newWstethMockedConfPct .
     */
    function setWstethMockedConfPct(uint64 newWstethMockedConfPct) external {
        _wstethMockedConfPct = newWstethMockedConfPct;
    }

    /// @notice Get current wsteth mocked price.
    function wstethMockedPrice() external view returns (uint256) {
        return _wstethMockedPrice;
    }

    /// @notice Get current wsteth mocked confidence interval.
    function wstethMockedConfPct() external view returns (uint64) {
        return _wstethMockedConfPct;
    }

    /// @notice Get constant wsteth mocked confidence interval denominator.
    function wstethMockedConfDenom() external pure returns (uint64) {
        return CONF_DENOM;
    }
}
