// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IVerifierProxy } from "../../../../src/interfaces/OracleMiddleware/IVerifierProxy.sol";

import { CHAINLINK_DATA_STREAMS_ETH_USD, PYTH_ETH_USD } from "../../../utils/Constants.sol";
import { ChainlinkDataStreamsFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of the `OracleMiddlewareWithDataStreams`.
 * @custom:background A deployed OracleMiddlewareWithDataStreams.
 */
contract TestChainlinkDataStreamsOracleMiddlewareParseAndValidatePriceRealData is ChainlinkDataStreamsFixture {
    using Strings for uint256;

    string internal constant TIMESTAMP_ERROR = "Wrong timestamp for";
    string internal constant PRICE_ERROR = "Wrong oracle middleware price for ";
    string internal constant BALANCE_ERROR = "Wrong balance";
    string internal constant VALIDATION_COST_ERROR = "Wrong validation cost";

    uint8 internal constant VALIDATE_OPEN_ACTION_INDEX = 7;
    string internal _validateOpenTimestampError =
        string.concat(TIMESTAMP_ERROR, actionNames[VALIDATE_OPEN_ACTION_INDEX]);
    string internal _validateOpenPriceError = string.concat(PRICE_ERROR, actionNames[VALIDATE_OPEN_ACTION_INDEX]);

    /**
     * @custom:scenario Parse and validate the price using Chainlink data streams API payload for all actions
     * and Pyth Hermes API signature for liquidations.
     * @custom:given The price feed is ETH/USD for both Chainlink and Pyth.
     * @custom:and The validation delay is respected.
     * @custom:when A Protocol action is performed.
     * @custom:then The price signature is well-decoded.
     * @custom:and The price retrieved by the oracle middleware matches the one
     * from the data streams API or the Hermes API.
     */
    function test_ForkFFIParseAndValidatePriceWithPythAndDataStreams() public {
        _setUp(_params);

        // Loop through all targeted actions
        for (uint256 i; i < actions.length; i++) {
            // Get the current action type
            ProtocolAction action = actions[i];

            // Construct error messages
            string memory timestampErrorMessage = string.concat(TIMESTAMP_ERROR, actionNames[i]);
            string memory priceErrorMessage = string.concat(PRICE_ERROR, actionNames[i]);

            // Validate data streams for Chainlink
            _parseAndValidateDataStreams(action, timestampErrorMessage, priceErrorMessage);

            // For liquidation actions, validate Pyth
            if (action == ProtocolAction.Liquidation) {
                _parseAndValidatePyth(action, timestampErrorMessage, priceErrorMessage);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with Chainlink data streams API payload using a fee manager.
     * @custom:given The price feed is ETH/USD for both Chainlink and Pyth.
     * @custom:and A mock fee manager is deployed.
     * @custom:when The `parseAndValidatePrice` function is called.
     * @custom:then The price signature is verified.
     * @custom:and The balance of the WETH in the mock fee manager equals the validation cost.
     */
    function test_ForkFFIParseAndValidatePriceFeeManager() public {
        _params.deployMockFeeManager = true;
        _setUp(_params);
        uint256 validationCost = _parseAndValidateDataStreams(
            actions[VALIDATE_OPEN_ACTION_INDEX], _validateOpenTimestampError, _validateOpenPriceError
        );
        assertGt(validationCost, 0, VALIDATION_COST_ERROR);
        assertEq(_weth.balanceOf(address(_mockFeeManager)), validationCost, BALANCE_ERROR);
    }

    /**
     * @custom:scenario Parse and validate price with Chainlink data streams API payload using a fee manager and full
     * native surcharge.
     * @custom:given The price feed is ETH/USD for both Chainlink and Pyth.
     * @custom:and A mock fee manager is deployed.
     * @custom:and A full native surcharge is set.
     * @custom:when The `parseAndValidatePrice` function is called.
     * @custom:then The price signature is verified.
     * @custom:and The balance of the WETH in the mock fee manager equals the validation cost.
     */
    function test_ForkFFIParseAndValidatePriceFeeManagerWithFullSurcharge() public {
        _params.deployMockFeeManager = true;
        _params.nativeSurchargeBps = PERCENTAGE_SCALAR;
        _setUp(_params);
        uint256 validationCost = _parseAndValidateDataStreams(
            actions[VALIDATE_OPEN_ACTION_INDEX], _validateOpenTimestampError, _validateOpenPriceError
        );
        assertGt(validationCost, 0, VALIDATION_COST_ERROR);
        assertEq(_weth.balanceOf(address(_mockFeeManager)), validationCost, BALANCE_ERROR);
    }

    /**
     * @custom:scenario Parse and validate price with Chainlink data streams API payload using a fee manager and full
     * discount.
     * @custom:given The price feed is ETH/USD for both Chainlink and Pyth.
     * @custom:and A mock fee manager is deployed.
     * @custom:when The `parseAndValidatePrice` function is called.
     * @custom:then The price signature is verified.
     * @custom:and The balance of the WETH in the mock fee manager is zero.
     */
    function test_ForkFFIParseAndValidatePriceFeeManagerWithFullDiscount() public {
        _params.deployMockFeeManager = true;
        _params.discountBps = PERCENTAGE_SCALAR;
        _setUp(_params);
        uint256 validationCost = _parseAndValidateDataStreams(
            actions[VALIDATE_OPEN_ACTION_INDEX], _validateOpenTimestampError, _validateOpenPriceError
        );
        assertEq(validationCost, 0, VALIDATION_COST_ERROR);
        assertEq(_weth.balanceOf(address(_mockFeeManager)), validationCost, BALANCE_ERROR);
    }

    /**
     * @notice Parses and validates the Chainlink data streams API payload.
     * @param action The USDN protocol action.
     * @param timestampErrorMessage The error message for timestamp validation failure.
     * @param priceErrorMessage The error message for price validation failure.
     */
    function _parseAndValidateDataStreams(
        ProtocolAction action,
        string memory timestampErrorMessage,
        string memory priceErrorMessage
    ) internal returns (uint256 validationCost_) {
        // Unverified payload from the Chainlink data streams API.
        bytes memory payload = _getChainlinkDataStreamsApiSignature(CHAINLINK_DATA_STREAMS_ETH_USD, block.timestamp);

        // Decode report data from the payload.
        (, bytes memory reportData) = abi.decode(payload, (bytes32[3], bytes));

        // Decode the unverified report.
        IVerifierProxy.ReportV3 memory unverifiedReport = abi.decode(reportData, (IVerifierProxy.ReportV3));

        // Calculate the validation cost for the given action and payload.
        validationCost_ = oracleMiddleware.validationCost(payload, action);

        // Initialize middleware price info.
        PriceInfo memory middlewarePrice;

        // Validate the price based on the action type.
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

        // Assert that the timestamp from the middleware price matches the block timestamp.
        assertEq(middlewarePrice.timestamp, block.timestamp, timestampErrorMessage);

        // Validate the price based on the action type.
        if (action == ProtocolAction.ValidateWithdrawal || action == ProtocolAction.ValidateOpenPosition) {
            // Ask price validation for withdrawal or open position actions.
            assertEq(middlewarePrice.price, uint192(unverifiedReport.ask), priceErrorMessage);
        } else if (action == ProtocolAction.ValidateDeposit || action == ProtocolAction.ValidateClosePosition) {
            // Bid price validation for deposit or close position actions.
            assertEq(middlewarePrice.price, uint192(unverifiedReport.bid), priceErrorMessage);
        } else {
            // Neutral price validation for other actions.
            assertEq(middlewarePrice.price, uint192(unverifiedReport.price), priceErrorMessage);
        }
    }

    /**
     * @dev Parses and validates the Pyth Hermes API signature.
     * @param action The USDN protocol action.
     * @param timestampErrorMessage The error message for timestamp validation failure.
     * @param priceErrorMessage The error message for price validation failure.
     */
    function _parseAndValidatePyth(
        ProtocolAction action,
        string memory timestampErrorMessage,
        string memory priceErrorMessage
    ) internal {
        // Retrieve Pyth data including price, decimals, timestamp, and signature bytes.
        (uint256 pythPrice,, uint256 pythDecimals, uint256 pythTimestamp, bytes memory data) =
            getHermesApiSignature(PYTH_ETH_USD, block.timestamp);

        // Calculate the validation cost for the given action and Pyth data.
        uint256 validationCost = oracleMiddleware.validationCost(data, action);

        // Since we force the usage of Pyth for initiate actions, Pyth requires
        // that the price data timestamp is recent compared to block.timestamp.
        vm.warp(pythTimestamp);

        // Parse and validate the price using the middleware.
        PriceInfo memory middlewarePrice =
            oracleMiddleware.parseAndValidatePrice{ value: validationCost }("", 0, action, data);

        // Format Pyth price to match the expected decimal precision.
        uint256 formattedPythPrice = pythPrice * 10 ** (oracleMiddleware.getDecimals() - pythDecimals);

        // Assert that the timestamp from the middleware price matches the Pyth timestamp.
        assertEq(middlewarePrice.timestamp, pythTimestamp, timestampErrorMessage);

        // Assert that the formatted Pyth price matches the price from the middleware.
        assertEq(middlewarePrice.price, formattedPythPrice, priceErrorMessage);
    }

    // Receive ether refunds
    receive() external payable { }
}
