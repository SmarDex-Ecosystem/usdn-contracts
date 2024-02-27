// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";

/**
 * @title Contract to apply and return a mocked wsteth price
 * @notice This contract is used to get the price of wsteth
 * by setting up a price or forward to wstethMiddleware.
 * This aim to simulate price up or down. Do not use it in production.
 */
contract MockWstEthOracleMiddleware is WstEthOracleMiddleware {
    /// @notice Confidence interval denominator
    uint16 internal constant CONF_DENOM = 10_000;
    /// @notice Confidence interval percentage numerator
    uint16 internal _wstethMockedConfPct = 20; // default 0.2% conf
    /**
     * @notice Wsteth mocked price
     * @dev This price will be used if greater than zero.
     */
    uint256 internal _wstethMockedPrice;
    /**
     * @notice If we need to verify the provided signature data or not.
     * @dev If _wstethMockedPrice == 0, this setting is ignored
     */
    bool internal _verifySignature = true;

    constructor(
        address pythContract,
        bytes32 pythPriceID,
        address chainlinkPriceFeed,
        address wsteth,
        uint256 chainlinkTimeElapsedLimit
    ) WstEthOracleMiddleware(pythContract, pythPriceID, chainlinkPriceFeed, wsteth, chainlinkTimeElapsedLimit) { }

    /// @inheritdoc OracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        public
        payable
        virtual
        override
        returns (PriceInfo memory price_)
    {
        // Parse and validate from parent wsteth middleware.
        // This aim to verify pyth price hermes signature in any case.
        if (_verifySignature || _wstethMockedPrice == 0) {
            price_ = super.parseAndValidatePrice(targetTimestamp, action, data);
        }

        // If mocked price is not set, return.
        if (_wstethMockedPrice == 0) {
            return price_;
        }

        // neutralPrice.
        price_.neutralPrice = _wstethMockedPrice;
        // price initialized with neutralPrice.
        price_.price = price_.neutralPrice;

        // ConfidenceInterval Down cases
        if (
            action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition
                || action == ProtocolAction.Liquidation
        ) {
            price_.price -= price_.price * _wstethMockedConfPct / CONF_DENOM;

            // ConfidenceInterval Up case
        } else if (action == ProtocolAction.ValidateOpenPosition) {
            price_.price += price_.price * _wstethMockedConfPct / CONF_DENOM;
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

    /// @inheritdoc OracleMiddleware
    function validationCost(bytes calldata data, ProtocolAction action)
        public
        view
        override
        returns (uint256 result_)
    {
        // No signature verification -> no oracle fee
        if (!_verifySignature) return 0;

        return super.validationCost(data, action);
    }

    /**
     * @notice Set Wsteth mocked confidence interval percentage.
     * @dev To calculate a percentage of neutral price up or down in some protocol actions.
     * @param newWstethMockedConfPct .
     */
    function setWstethMockedConfPct(uint16 newWstethMockedConfPct) external {
        require(newWstethMockedConfPct <= 1500, "15% max");
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

    /// @notice Set the signature verification flag.
    function setVerifySignature(bool verify) external {
        _verifySignature = verify;
    }
}
