// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IOracleMiddleware, PriceInfo } from "../interfaces/IOracleMiddleware.sol";
import { ProtocolAction } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { PythOracle } from "./oracles/PythOracle.sol";
import { ChainlinkOracle } from "./oracles/ChainlinkOracle.sol";

contract OracleMiddleware is IOracleMiddleware, PythOracle, ChainlinkOracle {
    uint8 constant DECIMALS = 8;

    constructor(address pythContract, bytes32 pythPriceID, address chainlinkPriceFeed)
        PythOracle(pythContract, pythPriceID)
        ChainlinkOracle(chainlinkPriceFeed)
    { }

    /* -------------------------------------------------------------------------- */
    /*                          Price retrieval features                          */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Parses and validates price data.
     * @dev The data format is specific to the middleware and is simply forwarded from the user transaction's calldata.
     * @param targetTimestamp The timestamp for which the price is requested. The middleware may use this to validate
     * whether the price is fresh enough.
     * @param action Type of action for which the price is requested. The middleware may use this to alter the
     * validation of the price or the returned price.
     * @param data Price data, the format varies from middleware to middleware and can be different depending on the
     * action.
     * @return result_ The price and timestamp as `PriceInfo`.
     */
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory result_)
    {
        if (action == ProtocolAction.None) {
            result_ = getPriceForNoneAction();
        } else if (action == ProtocolAction.InitiateDeposit) {
            result_ = getPriceForInitiateDepositAction();
        } else if (action == ProtocolAction.ValidateDeposit) {
            result_ = getPriceForValidateDepositAction();
        } else if (action == ProtocolAction.InitiateWithdrawal) {
            result_ = getPriceForInitiateWithdrawalAction();
        } else if (action == ProtocolAction.ValidateWithdrawal) {
            result_ = getPriceForValidateWithdrawalAction();
        } else if (action == ProtocolAction.InitiateOpenPosition) {
            result_ = getPriceForInitiateOpenPositionAction();
        } else if (action == ProtocolAction.ValidateOpenPosition) {
            result_ = getPriceForValidateOpenPositionAction();
        } else if (action == ProtocolAction.InitiateClosePosition) {
            result_ = getPriceForInitiateClosePositionAction();
        } else if (action == ProtocolAction.ValidateClosePosition) {
            result_ = getPriceForValidateClosePositionAction();
        } else if (action == ProtocolAction.Liquidation) {
            result_ = getPriceForLiquidationAction();
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                  Price retrieval for each possible action                  */
    /* -------------------------------------------------------------------------- */

    function getPriceForNoneAction() private returns (PriceInfo memory) { }

    function getPriceForInitiateDepositAction() private returns (PriceInfo memory) { }

    function getPriceForValidateDepositAction() private returns (PriceInfo memory) { }

    function getPriceForInitiateWithdrawalAction() private returns (PriceInfo memory) { }

    function getPriceForValidateWithdrawalAction() private returns (PriceInfo memory) { }

    function getPriceForInitiateOpenPositionAction() private returns (PriceInfo memory) { }

    function getPriceForValidateOpenPositionAction() private returns (PriceInfo memory) { }

    function getPriceForInitiateClosePositionAction() private returns (PriceInfo memory) { }

    function getPriceForValidateClosePositionAction() private returns (PriceInfo memory) { }

    function getPriceForLiquidationAction() private returns (PriceInfo memory) { }

    /* -------------------------------------------------------------------------- */
    /*                              Generic features                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns the number of decimals for the price (constant)
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice Returns the ETH cost of one price validation for the given action
    function validationCost(ProtocolAction action) external returns (uint256) { }
}
