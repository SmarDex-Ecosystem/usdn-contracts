// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

import { IBaseOracleMiddleware } from "../../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { OracleMiddleware } from "../OracleMiddleware.sol";
import { WstEthOracleMiddlewareWithRedstone } from "../WstEthOracleMiddlewareWithRedstone.sol";

/**
 * @title Contract to apply and return a mocked wstETH price
 * @notice This contract is used to get the price of wsteth by setting up a price or forwarding it to wstethMiddleware
 * @dev This aims at simulating price action. Do not use in production
 */
contract MockWstEthOracleMiddlewareWithRedstone is WstEthOracleMiddlewareWithRedstone {
    /// @notice Confidence interval percentage numerator
    uint16 internal _wstethMockedConfBps = 20; // default 0.2% conf

    /**
     * @notice Wsteth mocked price
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
        bytes32 redstoneFeedId,
        address chainlinkPriceFeed,
        address wsteth,
        uint256 chainlinkTimeElapsedLimit
    )
        WstEthOracleMiddlewareWithRedstone(
            pythContract,
            pythFeedId,
            redstoneFeedId,
            chainlinkPriceFeed,
            wsteth,
            chainlinkTimeElapsedLimit
        )
    { }

    /// @inheritdoc WstEthOracleMiddlewareWithRedstone
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) public payable override returns (PriceInfo memory price_) {
        // parse and validate from parent wsteth middleware
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

        // `ConfidenceInterval` down cases
        if (
            action == Types.ProtocolAction.ValidateDeposit || action == Types.ProtocolAction.ValidateClosePosition
                || action == Types.ProtocolAction.InitiateDeposit || action == Types.ProtocolAction.InitiateClosePosition
        ) {
            price_.price -= price_.price * _wstethMockedConfBps / BPS_DIVISOR;

            // `ConfidenceInterval` up case
        } else if (
            action == Types.ProtocolAction.ValidateWithdrawal || action == Types.ProtocolAction.ValidateOpenPosition
                || action == Types.ProtocolAction.InitiateWithdrawal || action == Types.ProtocolAction.InitiateOpenPosition
        ) {
            price_.price += price_.price * _wstethMockedConfBps / BPS_DIVISOR;
        }
    }

    /**
     * @notice Set Wsteth mocked price
     * @dev If the new mocked wsteth is greater than zero this will validate this mocked price else this will validate
     * the parent middleware price
     * @param newWstethMockedPrice The mock price to set
     */
    function setWstethMockedPrice(uint256 newWstethMockedPrice) external {
        _wstethMockedPrice = newWstethMockedPrice;
    }

    /**
     * @notice Set Wsteth mocked confidence interval percentage
     * @dev To calculate a percentage of the neutral price up or down in some protocol actions
     * @param newWstethMockedConfPct The mock confidence interval
     */
    function setWstethMockedConfBps(uint16 newWstethMockedConfPct) external {
        require(newWstethMockedConfPct <= 1500, "15% max");
        _wstethMockedConfBps = newWstethMockedConfPct;
    }

    /// @notice Get current wsteth mocked price
    function getWstethMockedPrice() external view returns (uint256) {
        return _wstethMockedPrice;
    }

    /// @notice Get current wsteth mocked confidence interval
    function getWstethMockedConfBps() external view returns (uint64) {
        return _wstethMockedConfBps;
    }

    /// @notice Get the signature verification flag
    function getVerifySignature() external view returns (bool) {
        return _verifySignature;
    }

    /// @notice Set the signature verification flag
    function setVerifySignature(bool verify) external {
        _verifySignature = verify;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function validationCost(bytes calldata data, Types.ProtocolAction action)
        public
        view
        override(IBaseOracleMiddleware, OracleMiddleware)
        returns (uint256 result_)
    {
        // no signature verification -> no oracle fee
        if (!_verifySignature) return 0;

        return super.validationCost(data, action);
    }
}
