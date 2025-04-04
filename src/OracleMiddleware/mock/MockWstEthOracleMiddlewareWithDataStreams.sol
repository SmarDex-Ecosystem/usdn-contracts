// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { CommonOracleMiddleware } from "../CommonOracleMiddleware.sol";
import { WstEthOracleMiddlewareWithDataStreams } from "../WstEthOracleMiddlewareWithDataStreams.sol";

/**
 * @title Contract to apply and return a mocked wstETH price
 * @notice This contract is used to get the price of wstETH by setting up a price or forwarding it to wstethMiddleware
 * @dev This aims at simulating price action. Do not use in production
 */
contract MockWstEthOracleMiddlewareWithDataStreams is WstEthOracleMiddlewareWithDataStreams {
    /**
     * @notice wstETH mocked price
     * @dev This price will be used if greater than zero
     */
    uint256 internal _wstethMockedPrice;
    /**
     * @notice If we need to verify the provided signature data or not
     * @dev If _wstethMockedPrice == 0, this setting is ignored
     */
    bool internal _verifySignature = true;

    constructor(
        address pythContract,
        bytes32 pythFeedId,
        address chainlinkPriceFeed,
        address wsteth,
        uint256 chainlinkTimeElapsedLimit,
        address chainlinkProxyVerifierAddress,
        bytes32 chainlinkStreamId
    )
        WstEthOracleMiddlewareWithDataStreams(
            pythContract,
            pythFeedId,
            chainlinkPriceFeed,
            wsteth,
            chainlinkTimeElapsedLimit,
            chainlinkProxyVerifierAddress,
            chainlinkStreamId
        )
    { }

    /// @inheritdoc CommonOracleMiddleware
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) public payable override returns (PriceInfo memory price_) {
        // parse and validate from parent WstEth middleware
        // this aims to verify pyth price hermes signature in any case
        if (_verifySignature || _wstethMockedPrice == 0) {
            price_ = super.parseAndValidatePrice(actionId, targetTimestamp, action, data);
        } else {
            price_.timestamp = targetTimestamp == 0 ? block.timestamp : targetTimestamp;
        }

        // if the mocked price is not set, return
        if (_wstethMockedPrice == 0) {
            return price_;
        }

        price_.neutralPrice = _wstethMockedPrice;
        price_.price = price_.neutralPrice;

        // `PriceAdjustment` down cases bid price
        if (
            action == Types.ProtocolAction.ValidateDeposit || action == Types.ProtocolAction.ValidateClosePosition
                || action == Types.ProtocolAction.InitiateDeposit || action == Types.ProtocolAction.InitiateClosePosition
        ) {
            price_.price -= price_.price * 100 / 10_000;

            // `PriceAdjustment` up case ask price
        } else if (
            action == Types.ProtocolAction.ValidateWithdrawal || action == Types.ProtocolAction.ValidateOpenPosition
                || action == Types.ProtocolAction.InitiateWithdrawal || action == Types.ProtocolAction.InitiateOpenPosition
        ) {
            price_.price += price_.price * 100 / 10_000;
        }
    }

    /**
     * @notice Set WstEth mocked price
     * @dev If the new mocked WstEth is greater than zero this will validate this mocked price else this will validate
     * the parent middleware price
     * @param newWstethMockedPrice The mock price to set
     */
    function setWstethMockedPrice(uint256 newWstethMockedPrice) external {
        _wstethMockedPrice = newWstethMockedPrice;
    }

    /// @notice Get current WstEth mocked price
    function getWstethMockedPrice() external view returns (uint256) {
        return _wstethMockedPrice;
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
        override
        returns (uint256 result_)
    {
        // no signature verification -> no oracle fee
        if (!_verifySignature) return 0;

        return super.validationCost(data, action);
    }
}
