// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IBaseOracleMiddleware } from "../../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { CommonOracleMiddleware } from "../CommonOracleMiddleware.sol";
import { OracleMiddlewareWithPyth } from "../OracleMiddlewareWithPyth.sol";

/**
 * @title Contract to apply and return a mocked price for standard underlying ERC20 tokens.
 * @notice This contract is used to mock the price returned by the price feeds and apply a chosen confidence interval.
 * @dev This aims at simulating price action. Do not use in production.
 */
contract MockOracleMiddlewareWithPyth is OracleMiddlewareWithPyth {
    /// @notice Confidence interval numerator (in basis points)
    uint16 internal _mockedConfBps = 20; // default 0.2% conf

    /**
     * @notice Mocked price
     * @dev This price will be used if greater than zero
     */
    uint256 internal _mockedPrice;
    /**
     * @notice If we need to verify the provided signature data or not
     * @dev If _mockedPrice == 0, this setting is ignored
     */
    bool internal _verifySignature = true;

    constructor(address pythContract, bytes32 pythFeedId, address chainlinkPriceFeed, uint256 chainlinkTimeElapsedLimit)
        OracleMiddlewareWithPyth(pythContract, pythFeedId, chainlinkPriceFeed, chainlinkTimeElapsedLimit)
    { }

    /// @inheritdoc CommonOracleMiddleware
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) public payable override(IBaseOracleMiddleware, CommonOracleMiddleware) returns (PriceInfo memory price_) {
        // parse and validate from parent middleware
        // this aims to verify pyth price hermes signature in any case
        if (_verifySignature || _mockedPrice == 0) {
            price_ = super.parseAndValidatePrice(actionId, targetTimestamp, action, data);
        } else {
            price_.timestamp = targetTimestamp == 0 ? block.timestamp : targetTimestamp;
        }

        // if the mocked price is not set, return
        if (_mockedPrice == 0) {
            return price_;
        }

        price_.neutralPrice = _mockedPrice;
        price_.price = price_.neutralPrice;

        // `PriceAdjustment` down cases
        if (
            action == Types.ProtocolAction.ValidateDeposit || action == Types.ProtocolAction.ValidateClosePosition
                || action == Types.ProtocolAction.InitiateDeposit || action == Types.ProtocolAction.InitiateClosePosition
        ) {
            price_.price -= price_.price * _mockedConfBps / BPS_DIVISOR;

            // `PriceAdjustment` up case
        } else if (
            action == Types.ProtocolAction.ValidateWithdrawal || action == Types.ProtocolAction.ValidateOpenPosition
                || action == Types.ProtocolAction.InitiateWithdrawal || action == Types.ProtocolAction.InitiateOpenPosition
        ) {
            price_.price += price_.price * _mockedConfBps / BPS_DIVISOR;
        }
    }

    /**
     * @notice Sets the price to use when {parseAndValidatePrice} is called.
     * @dev If the new mocked price is greater than zero this will validate this mocked price else this will validate
     * the parent middleware price.
     * @param newMockedPrice The price used when {parseAndValidatePrice} is called.
     */
    function setMockedPrice(uint256 newMockedPrice) external {
        _mockedPrice = newMockedPrice;
    }

    /**
     * @notice Sets the confidence interval to apply to the mocked price.
     * @dev To calculate a percentage of the neutral price up or down in some protocol actions.
     * @param newMockedConfPct The mock confidence interval.
     */
    function setMockedConfBps(uint16 newMockedConfPct) external {
        require(newMockedConfPct <= 1500, "15% max");
        _mockedConfBps = newMockedConfPct;
    }

    /// @notice Get current mocked price
    function getMockedPrice() external view returns (uint256) {
        return _mockedPrice;
    }

    /// @notice Get current mocked confidence interval
    function getMockedConfBps() external view returns (uint64) {
        return _mockedConfBps;
    }

    /// @notice Get the signature verification flag
    function getVerifySignature() external view returns (bool) {
        return _verifySignature;
    }

    /// @notice Set the signature verification flag
    function setVerifySignature(bool verify) external {
        _verifySignature = verify;
    }

    /// @inheritdoc CommonOracleMiddleware
    function validationCost(bytes calldata data, Types.ProtocolAction action)
        public
        view
        override(IBaseOracleMiddleware, CommonOracleMiddleware)
        returns (uint256 result_)
    {
        // no signature verification -> no oracle fee
        if (!_verifySignature) return 0;

        return super.validationCost(data, action);
    }
}
