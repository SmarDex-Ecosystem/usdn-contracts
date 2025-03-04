// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IVerifierProxy } from "../../../../src/interfaces/OracleMiddleware/IVerifierProxy.sol";

import { CHAINLINK_DATA_STREAM_ETH_USD, PYTH_ETH_USD } from "../../../utils/Constants.sol";
import { ChainlinkDataStreamFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddlewareWithChainlinkDataStream`.
 * @custom:background A deployed OracleMiddlewareWithChainlinkDataStream.
 */
contract TestChainlinkDataStreamOracleMiddlewareParseAndValidatePriceRealData is ChainlinkDataStreamFixture {
    using Strings for uint256;

    string internal constant TIMESTAMP_ERROR = "Wrong timestamp for";
    string internal constant PRICE_ERROR = "Wrong oracle middleware price for ";
    string internal constant BALANCE_ERROR = "Wrong balance";
    string internal constant VALIDATION_COST_ERROR = "Wrong validation cost";

    // validate open
    uint8 internal constant VALIDATE_OPEN_ACTION_INDEX = 7;
    string internal _validateOpenTimestampError =
        string.concat(TIMESTAMP_ERROR, actionNames[VALIDATE_OPEN_ACTION_INDEX]);
    string internal _validateOpenPriceError = string.concat(PRICE_ERROR, actionNames[VALIDATE_OPEN_ACTION_INDEX]);

    /**
     * @custom:scenario Parse and validate price with chainlink data stream API payload for all actions
     * and pyth hermes API signature for liquidations.
     * @custom:given The price feed is ETH/USD for chainlink and pyth.
     * @custom:and The validation delay is respected.
     * @custom:when The Protocol action is any targeted action.
     * @custom:then The price signature is well-decoded.
     * @custom:and The price retrieved by the oracle middleware is the same as the one
     * from the data stream API or the hermes API.
     */
    function test_ForkFFIParseAndValidatePriceWithPythAndDataStream() public {
        _setUp(_params);

        // all targeted actions loop
        for (uint256 i; i < actions.length; i++) {
            // action type
            ProtocolAction action = actions[i];

            // error messages
            string memory timestampErrorMessage = string.concat(TIMESTAMP_ERROR, actionNames[i]);
            string memory priceErrorMessage = string.concat(PRICE_ERROR, actionNames[i]);

            // chainlink data stream
            _parseAndValidateDataStream(action, timestampErrorMessage, priceErrorMessage);

            // for liquidation pyth is accepted
            if (action == ProtocolAction.Liquidation) {
                _parseAndValidatePyth(action, timestampErrorMessage, priceErrorMessage);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with chainlink data stream API payload with a fee manager.
     * @custom:given The price feed is ETH/USD for chainlink and pyth.
     * @custom:and A mock fee manager is deployed.
     * @custom:when The `parseAndValidatePrice` function is called.
     * @custom:then The price signature is verified.
     * @custom:and The `weth` fee manager balance is equal to the validation cost.
     */
    function test_ForkFFIParseAndValidatePriceFeeManager() public {
        _params.deployMockFeeManager = true;
        _setUp(_params);
        uint256 validationCost = _parseAndValidateDataStream(
            actions[VALIDATE_OPEN_ACTION_INDEX], _validateOpenTimestampError, _validateOpenPriceError
        );
        assertGt(validationCost, 0, VALIDATION_COST_ERROR);
        assertEq(_weth.balanceOf(address(_mockFeeManager)), validationCost, BALANCE_ERROR);
    }

    /**
     * @custom:scenario Parse and validate price with chainlink data stream API payload with a fee manager and a full
     * native surcharge.
     * @custom:given The price feed is ETH/USD for chainlink and pyth.
     * @custom:and A mock fee manager is deployed.
     * @custom:and A full native surcharge is set.
     * @custom:when The `parseAndValidatePrice` function is called.
     * @custom:then The price signature is verified.
     * @custom:and The `weth` fee manager balance is equal to the validation cost.
     */
    function test_ForkFFIParseAndValidatePriceFeeManagerWithFullSurcharge() public {
        _params.deployMockFeeManager = true;
        _params.nativeSurchargeBps = PERCENTAGE_SCALAR;
        _setUp(_params);
        uint256 validationCost = _parseAndValidateDataStream(
            actions[VALIDATE_OPEN_ACTION_INDEX], _validateOpenTimestampError, _validateOpenPriceError
        );
        assertGt(validationCost, 0, VALIDATION_COST_ERROR);
        assertEq(_weth.balanceOf(address(_mockFeeManager)), validationCost, BALANCE_ERROR);
    }

    /**
     * @custom:scenario Parse and validate price with chainlink data stream API payload with a fee manager and a full
     * discount.
     * @custom:given The price feed is ETH/USD for chainlink and pyth.
     * @custom:and A mock fee manager is deployed.
     * @custom:when The `parseAndValidatePrice` function is called.
     * @custom:then The price signature is verified.
     * @custom:and The `weth` fee manager balance is equal zero.
     */
    function test_ForkFFIParseAndValidatePriceFeeManagerWithFullDiscount() public {
        _params.deployMockFeeManager = true;
        _params.discountBps = PERCENTAGE_SCALAR;
        _setUp(_params);
        uint256 validationCost = _parseAndValidateDataStream(
            actions[VALIDATE_OPEN_ACTION_INDEX], _validateOpenTimestampError, _validateOpenPriceError
        );
        assertEq(validationCost, 0, VALIDATION_COST_ERROR);
        assertEq(_weth.balanceOf(address(_mockFeeManager)), validationCost, BALANCE_ERROR);
    }

    /**
     * @notice Parses and validates the chainlink data stream API payload.
     * @param action The usdn protocol action.
     * @param timestampErrorMessage The action timestamp error message.
     * @param priceErrorMessage The action price error message.
     */
    function _parseAndValidateDataStream(
        ProtocolAction action,
        string memory timestampErrorMessage,
        string memory priceErrorMessage
    ) internal returns (uint256 validationCost_) {
        // unverified payload
        bytes memory payload = _getChainlinkDatastreamApiSignature(CHAINLINK_DATA_STREAM_ETH_USD, block.timestamp);
        // decode report data
        (, bytes memory reportData) = abi.decode(payload, (bytes32[3], bytes));
        // decode unverified report
        IVerifierProxy.ReportV3 memory unverifiedReport = abi.decode(reportData, (IVerifierProxy.ReportV3));
        // validation cost
        validationCost_ = oracleMiddleware.validationCost(payload, action);
        // middleware data
        PriceInfo memory middlewarePrice;
        if (
            action == ProtocolAction.Initialize || action == ProtocolAction.Liquidation
                || action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
        ) {
            middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost_ }("", 0, action, payload);
        } else {
            middlewarePrice = oracleMiddleware.parseAndValidatePrice{ value: validationCost_ }(
                "", uint128(block.timestamp - oracleMiddleware.getValidationDelay()), action, payload
            );
        }

        // timestamp assertion
        assertEq(middlewarePrice.timestamp, block.timestamp, timestampErrorMessage);
        // ask price
        if (action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition) {
            assertEq(middlewarePrice.price, uint192(unverifiedReport.ask), priceErrorMessage);
        }
        // bid price
        else if (action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition) {
            assertEq(middlewarePrice.price, uint192(unverifiedReport.bid), priceErrorMessage);
        }
        // neutral price
        else {
            assertEq(middlewarePrice.price, uint192(unverifiedReport.price), priceErrorMessage);
        }
    }

    /**
     * @dev Parses and validates the pyth hermes API signature.
     * @param action The usdn protocol action.
     * @param timestampErrorMessage The action timestamp error message.
     * @param priceErrorMessage The action price error message.
     */
    function _parseAndValidatePyth(
        ProtocolAction action,
        string memory timestampErrorMessage,
        string memory priceErrorMessage
    ) internal {
        // pyth data
        (uint256 pythPrice,, uint256 pythDecimals, uint256 pythTimestamp, bytes memory data) =
            getHermesApiSignature(PYTH_ETH_USD, block.timestamp);
        // validation cost
        uint256 validationCost = oracleMiddleware.validationCost(data, action);
        // since we force the usage of Pyth for initiate actions, Pyth requires
        // that the price data timestamp is recent compared to block.timestamp
        vm.warp(pythTimestamp);
        PriceInfo memory middlewarePrice =
            oracleMiddleware.parseAndValidatePrice{ value: validationCost }("", 0, action, data);
        // format price decimals
        uint256 formattedPythPrice = pythPrice * 10 ** (oracleMiddleware.getDecimals() - pythDecimals);
        // timestamp assertion
        assertEq(middlewarePrice.timestamp, pythTimestamp, timestampErrorMessage);
        // price assertion
        assertEq(middlewarePrice.price, formattedPythPrice, priceErrorMessage);
    }

    // receive ether refunds
    receive() external payable { }
}
