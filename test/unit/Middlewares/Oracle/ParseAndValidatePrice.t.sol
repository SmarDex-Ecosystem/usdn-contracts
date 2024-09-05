// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { ETH_CONF, ETH_DECIMALS, ETH_PRICE, MOCK_PYTH_DATA } from "../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";
import { IMockPythError } from "../utils/MockPyth.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestOracleMiddlewareParseAndValidatePrice is OracleMiddlewareBaseFixture, IMockPythError {
    using Strings for uint256;

    uint256 internal immutable FORMATTED_ETH_PRICE;
    uint256 internal immutable FORMATTED_ETH_CONF;
    uint128 internal immutable LOW_LATENCY_DELAY;
    uint128 internal immutable TARGET_TIMESTAMP;
    uint128 internal immutable LIMIT_TIMESTAMP;
    uint80 internal immutable FIRST_ROUND_ID = (1 << 64) + 1;

    constructor() {
        super.setUp();

        FORMATTED_ETH_PRICE = (ETH_PRICE * (10 ** oracleMiddleware.getDecimals())) / 10 ** ETH_DECIMALS;
        FORMATTED_ETH_CONF = (ETH_CONF * (10 ** oracleMiddleware.getDecimals())) / 10 ** ETH_DECIMALS
            * oracleMiddleware.getConfRatioBps() / oracleMiddleware.BPS_DIVISOR();

        LOW_LATENCY_DELAY = uint128(oracleMiddleware.getLowLatencyDelay());
        TARGET_TIMESTAMP = uint128(block.timestamp);
        LIMIT_TIMESTAMP = TARGET_TIMESTAMP + LOW_LATENCY_DELAY;
    }

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is a value that is not supported
     * @custom:then The call reverts
     */
    function test_RevertWhen_parseAndValidatePriceWithUnsupportedAction() public {
        (bool success, bytes memory data) = address(oracleMiddleware).call(
            abi.encodeWithSelector(
                oracleMiddleware.parseAndValidatePrice.selector,
                uint128(TARGET_TIMESTAMP - oracleMiddleware.getValidationDelay()),
                11,
                MOCK_PYTH_DATA
            )
        );

        assertEq(success, false, "Function should revert");
        assertEq(data.length, 0, "Function should revert");
    }

    /**
     * @custom:scenario Parse and validate price with Pyth when data is provided
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:and Non-empty data was given
     * @custom:when Calling parseAndValidatePrice
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceWithPythForAllActions() public {
        // Give a slightly different price for chainlink to be able to differentiate the oracles responses
        // If for a reason or another the chainlink price is used, tests will fail
        int256 mockedChainlinkPrice = int256(ETH_PRICE - 1);
        mockChainlinkOnChain.setLatestRoundData(1, mockedChainlinkPrice, TARGET_TIMESTAMP, 1);

        for (uint256 i; i < actions.length; i++) {
            Types.ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
                value: oracleMiddleware.validationCost(MOCK_PYTH_DATA, action)
            }("", uint128(TARGET_TIMESTAMP - oracleMiddleware.getValidationDelay()), action, MOCK_PYTH_DATA);

            // Price + conf
            if (
                action == Types.ProtocolAction.InitiateWithdrawal || action == Types.ProtocolAction.ValidateWithdrawal
                    || action == Types.ProtocolAction.InitiateOpenPosition
                    || action == Types.ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(price.price, FORMATTED_ETH_PRICE + FORMATTED_ETH_CONF, errorMessage);
            }
            // Price - conf
            else if (
                action == Types.ProtocolAction.InitiateDeposit || action == Types.ProtocolAction.ValidateDeposit
                    || action == Types.ProtocolAction.InitiateClosePosition
                    || action == Types.ProtocolAction.ValidateClosePosition
            ) {
                assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, errorMessage);
            } else {
                assertEq(price.price, FORMATTED_ETH_PRICE, errorMessage);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price for "initiate" actions using chainlink when empty data is provided
     * @custom:given Empty data is provided
     * @custom:when Calling parseAndValidatePrice for "initiate" actions
     * @custom:then It returns the onchain price from chainlink
     */
    function test_getPriceFromChainlinkWhenEmptyDataIsProvided() public {
        // Give a slightly different price for chainlink to be able to differentiate the oracles responses
        int256 mockedChainlinkPrice = int256(ETH_PRICE - 1);
        uint256 mockedChainlinkFormattedPrice = FORMATTED_ETH_PRICE - 1e10;
        mockChainlinkOnChain.setLatestRoundData(1, mockedChainlinkPrice, TARGET_TIMESTAMP, 1);

        PriceInfo memory priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.Initialize, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateDeposit, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateWithdrawal, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateOpenPosition, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateClosePosition, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);
    }

    /**
     * @custom:scenario Call to parseAndValidatePrice for "initiate" actions still works when Pyth reverts
     * @custom:given Empty data is provided and calls to the Pyth oracle revert
     * @custom:when Calling parseAndValidatePrice for "initiate" actions
     * @custom:then It returns the onchain price from chainlink without reverting
     */
    function test_getPriceFromChainlinkWhenPythReverts() public {
        mockPyth.toggleRevert();

        mockChainlinkOnChain.setLatestRoundData(1, int256(ETH_PRICE), TARGET_TIMESTAMP, 1);

        PriceInfo memory priceInfo = oracleMiddleware.parseAndValidatePrice("", 0, Types.ProtocolAction.Initialize, "");
        assertEq(priceInfo.price, FORMATTED_ETH_PRICE);

        priceInfo = oracleMiddleware.parseAndValidatePrice("", 0, Types.ProtocolAction.InitiateDeposit, "");
        assertEq(priceInfo.price, FORMATTED_ETH_PRICE);

        priceInfo = oracleMiddleware.parseAndValidatePrice("", 0, Types.ProtocolAction.InitiateWithdrawal, "");
        assertEq(priceInfo.price, FORMATTED_ETH_PRICE);

        priceInfo = oracleMiddleware.parseAndValidatePrice("", 0, Types.ProtocolAction.InitiateOpenPosition, "");
        assertEq(priceInfo.price, FORMATTED_ETH_PRICE);

        priceInfo = oracleMiddleware.parseAndValidatePrice("", 0, Types.ProtocolAction.InitiateClosePosition, "");
        assertEq(priceInfo.price, FORMATTED_ETH_PRICE);
    }

    /**
     * @custom:scenario Parse and validate price for "validate" actions using chainlink with a roundId data
     * @custom:given The chainlink validate roundId data
     * @custom:and A correct chainlink previous roundId
     * @custom:and A correct chainlink validate roundId
     * @custom:when Calling parseAndValidatePrice for "validate" actions after waiting the low latency delay
     * @custom:then It returns the onchain price from chainlink
     */
    function test_getValidatePriceFromChainlinkRoundId() public {
        (, int256 mockedChainlinkPrice,,,) = mockChainlinkOnChain.getRoundData(0);

        mockChainlinkOnChain.setRoundTimestamp(0, LIMIT_TIMESTAMP);
        mockChainlinkOnChain.setRoundTimestamp(1, LIMIT_TIMESTAMP + 1);

        uint256 mockedChainlinkFormattedPrice =
            uint256(mockedChainlinkPrice) * 10 ** (oracleMiddleware.getDecimals() - mockChainlinkOnChain.decimals());
        bytes memory roundIdData = abi.encode(uint80(1));

        skip(LOW_LATENCY_DELAY + 1);

        PriceInfo memory priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateWithdrawal, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateOpenPosition, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateClosePosition, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);
    }

    /**
     * @custom:scenario Parse and validate price for "validate" actions using chainlink, roundId is too high
     * @custom:given The previous roundId has a timestamp later than the limit timestamp
     * @custom:when The `parseAndValidatePrice` for "validate" actions is called with a roundId that is too high
     * @custom:then It should revert with `OracleMiddlewareInvalidRoundId`
     */
    function test_RevertWhen_getValidatePriceFromChainlinkRoundIdTooHigh() public {
        mockChainlinkOnChain.setRoundTimestamp(0, LIMIT_TIMESTAMP + 1);
        mockChainlinkOnChain.setRoundTimestamp(1, LIMIT_TIMESTAMP + 2);

        bytes memory roundIdData = abi.encode(uint80(1));
        bytes4 errorSelector = OracleMiddlewareInvalidRoundId.selector;

        skip(LOW_LATENCY_DELAY + 1);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateWithdrawal, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateOpenPosition, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateClosePosition, roundIdData
        );
    }

    /**
     * @custom:scenario Parse and validate price for "validate" actions using chainlink, roundId is too low
     * @custom:given The roundId has a timestamp equal to the limit timestamp
     * @custom:when The parseAndValidatePrice for "validate" actions is called with a roundId that is too low
     * @custom:then It should revert with OracleMiddlewareInvalidRoundId
     */
    function test_RevertWhen_getValidatePriceFromChainlinkRoundIdTooLow() public {
        mockChainlinkOnChain.setRoundTimestamp(0, LIMIT_TIMESTAMP - 1);
        mockChainlinkOnChain.setRoundTimestamp(1, LIMIT_TIMESTAMP);

        bytes memory roundIdData = abi.encode(uint80(1));
        bytes4 errorSelector = OracleMiddlewareInvalidRoundId.selector;

        skip(LOW_LATENCY_DELAY + 1);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateWithdrawal, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateOpenPosition, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateClosePosition, roundIdData
        );
    }

    /**
     * @custom:scenario Parse and validate price using pyth
     * @custom:given ETH price is -1 USD in pyth oracle
     * @custom:and The chainlink oracle is functional
     * @custom:and The validation delay is respected
     * @custom:then It reverts when validating price for all action using Pyth oracle
     */
    function test_RevertWhen_parseAndValidatePriceWithNegativeEthPrice() public {
        // Update price to -1 USD in pyth oracle
        mockPyth.setPrice(-1);
        uint256 timestamp = TARGET_TIMESTAMP - oracleMiddleware.getValidationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.None, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateWithdrawal, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateOpenPosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateClosePosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );

        /* --------------------- Initiate actions revert as well -------------------- */

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateDeposit, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateWithdrawal, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateOpenPosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateClosePosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.Initialize, MOCK_PYTH_DATA
        );

        /* --------------------- Validate actions revert as well -------------------- */

        skip(LOW_LATENCY_DELAY + 1);

        // wrong validate roundId price

        bytes memory roundIdData = abi.encode(FIRST_ROUND_ID + 1);
        mockChainlinkOnChain.setRoundTimestamp(FIRST_ROUND_ID, LIMIT_TIMESTAMP);
        mockChainlinkOnChain.setRoundTimestamp(FIRST_ROUND_ID + 1, LIMIT_TIMESTAMP + 1);
        mockChainlinkOnChain.setRoundPrice(FIRST_ROUND_ID, int256(ETH_PRICE));
        mockChainlinkOnChain.setRoundPrice(FIRST_ROUND_ID + 1, -1);
        mockChainlinkOnChain.setLatestRoundData(FIRST_ROUND_ID + 1, -1, LIMIT_TIMESTAMP + 1, FIRST_ROUND_ID + 1);

        validationCost = oracleMiddleware.validationCost(roundIdData, Types.ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateWithdrawal, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateOpenPosition, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateClosePosition, roundIdData
        );
    }

    /**
     * @custom:scenario Parse and validate price using Chainlink that recently changed aggregator
     * @custom:given Enough time has passed that Chainlink is used to validate the pending action
     * @custom:and The latest round ID is the first ID of the phase
     * @custom:and The validation delay is respected
     * @custom:and The price timestamp is below the time elapsed limit
     * @custom:then It returns the price data of the provided round ID
     */
    function test_parseAndValidatePriceWithFirstRoundIdOfPhase() public {
        bytes memory roundIdData = abi.encode(FIRST_ROUND_ID);

        mockChainlinkOnChain.setRoundData(
            FIRST_ROUND_ID, int256(ETH_PRICE), LIMIT_TIMESTAMP + 1, LIMIT_TIMESTAMP + 1, FIRST_ROUND_ID
        );
        mockChainlinkOnChain.setLatestRoundData(FIRST_ROUND_ID, int256(ETH_PRICE), LIMIT_TIMESTAMP + 1, FIRST_ROUND_ID);
        uint256 mockedChainlinkFormattedPrice =
            ETH_PRICE * 10 ** (oracleMiddleware.getDecimals() - mockChainlinkOnChain.decimals());

        skip(LOW_LATENCY_DELAY + 1);

        // sanity check
        assertEq(FIRST_ROUND_ID, (1 << 64) + 1, "The first round ID should be the first valid round of the phase");

        PriceInfo memory priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice, "Price should be equal to the provided round's price");
    }

    /**
     * @custom:scenario Parse and validate price using Chainlink with the first round ID of a previous phase
     * @custom:given Enough time has passed that Chainlink is used to validate the pending action
     * @custom:and The latest round ID is in a newer phase than the provided round ID
     * @custom:and The validation delay is respected
     * @custom:and The price timestamp is below the time elapsed limit
     * @custom:then It reverts with a OracleMiddlewareInvalidRoundId error
     */
    function test_RevertWhen_parseAndValidatePriceWithFirstRoundIdOfPreviousPhase() public {
        bytes memory roundIdData = abi.encode(FIRST_ROUND_ID);

        mockChainlinkOnChain.setRoundData(
            FIRST_ROUND_ID, int256(ETH_PRICE), LIMIT_TIMESTAMP + 1, LIMIT_TIMESTAMP + 1, FIRST_ROUND_ID
        );
        // set the latest round data with a round ID from a newer phase
        mockChainlinkOnChain.setLatestRoundData((2 << 64) + 1, int256(ETH_PRICE), LIMIT_TIMESTAMP + 2, FIRST_ROUND_ID);

        skip(LOW_LATENCY_DELAY + 1);

        // sanity check
        assertEq(FIRST_ROUND_ID, (1 << 64) + 1, "The first round ID should be the first valid round of the phase");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareInvalidRoundId.selector));
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData);
    }

    /**
     * @custom:scenario Parse and validate price using Chainlink with the first round ID of a new, too recent phase
     * @custom:given Enough time has passed that Chainlink is used to validate the pending action
     * @custom:and The latest round ID is the first ID of the phase
     * @custom:and The validation delay is respected
     * @custom:and The price is above the time elapsed limit
     * @custom:then It reverts with a OracleMiddlewareInvalidRoundId error
     */
    function test_RevertWhen_parseAndValidatePriceWithFirstRoundIdOfPhaseTooNew() public {
        bytes memory roundIdData = abi.encode(FIRST_ROUND_ID);

        mockChainlinkOnChain.setRoundData(
            FIRST_ROUND_ID,
            int256(ETH_PRICE),
            LIMIT_TIMESTAMP + chainlinkTimeElapsedLimit + 1,
            LIMIT_TIMESTAMP + chainlinkTimeElapsedLimit + 1,
            FIRST_ROUND_ID
        );
        mockChainlinkOnChain.setLatestRoundData(
            FIRST_ROUND_ID, int256(ETH_PRICE), LIMIT_TIMESTAMP + chainlinkTimeElapsedLimit + 1, FIRST_ROUND_ID
        );

        skip(LOW_LATENCY_DELAY + 1);

        // sanity check
        assertEq(FIRST_ROUND_ID, (1 << 64) + 1, "The first round ID should be the first valid round of the phase");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareInvalidRoundId.selector));
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData);
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given Pyth oracle reverts
     * @custom:and The validationDelay is respected
     * @custom:then It reverts when validating price for all action using Pyth oracle
     */
    function test_RevertWhen_parseAndValidatePriceWhileOracleMiddlewarePythValidationFailed() public {
        // Update price to -1 USD in pyth oracle
        mockPyth.toggleRevert();
        uint256 timestamp = TARGET_TIMESTAMP - oracleMiddleware.getValidationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.None, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateWithdrawal, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateOpenPosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateClosePosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );

        /* ---------- Initiate actions revert if data provided is not empty --------- */

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateDeposit, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateWithdrawal, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateOpenPosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateClosePosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.Initialize, MOCK_PYTH_DATA
        );
    }

    /**
     * @custom:scenario Parse and validate price
     * @custom:given Pyth oracle reverts
     * @custom:and The validationDelay is respected
     * @custom:then It reverts when validating price and initiating positions for all actions using Pyth oracle
     */
    function test_RevertWhen_parseAndValidatePriceWhileAllValidationFailed() public {
        // Update price to -1 USD in oracles
        mockPyth.toggleRevert();

        uint256 timestamp = TARGET_TIMESTAMP - oracleMiddleware.getValidationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.None, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateWithdrawal, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateOpenPosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.ValidateClosePosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );

        /* ------------------ All initiate actions revert as well ------------------ */

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.Initialize, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateDeposit, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateWithdrawal, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateOpenPosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateClosePosition, MOCK_PYTH_DATA
        );
    }

    /**
     * @custom:scenario Parse and validate price for "Initiate" actions fails when no data is provided and chainlink's
     * data is too old
     * @custom:given Chainlink oracle's data's timestamp is too old
     * @custom:and Empty data has been provided
     * @custom:then It reverts with a OracleMiddlewarePriceTooOld error
     */
    function test_RevertWhen_ChainlinkPriceIsTooOld() public {
        uint256 timestamp = TARGET_TIMESTAMP - oracleMiddleware.getChainlinkTimeElapsedLimit();
        uint256 tooOldTimestamp = timestamp - 1;

        // Set chainlink's data's last timestamp to something too old
        mockChainlinkOnChain.setLastPublishTime(tooOldTimestamp);
        mockChainlinkOnChain.setLatestRoundData(1, oracleMiddleware.PRICE_TOO_OLD(), tooOldTimestamp, 1);

        uint256 validationCost = oracleMiddleware.validationCost("", Types.ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        PriceInfo memory priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.Initialize, ""
        );

        validationCost = oracleMiddleware.validationCost("", Types.ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateDeposit, ""
        );

        validationCost = oracleMiddleware.validationCost("", Types.ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateWithdrawal, ""
        );

        validationCost = oracleMiddleware.validationCost("", Types.ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateOpenPosition, ""
        );

        validationCost = oracleMiddleware.validationCost("", Types.ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), Types.ProtocolAction.InitiateClosePosition, ""
        );
    }

    /**
     * @custom:scenario Parse and validate price for "Initiate" actions fails when no data is provided and chainlink's
     * price is invalid
     * @custom:given Chainlink oracle's data's price is less than 0
     * @custom:and Empty data has been provided
     * @custom:then It reverts with a OracleMiddlewareWrongPrice error
     */
    function test_RevertWhen_ChainlinkPriceIsWrong() public {
        // Set chainlink's data's last timestamp to something too old
        mockChainlinkOnChain.setLastPublishTime(TARGET_TIMESTAMP);
        mockChainlinkOnChain.setLatestRoundData(1, -1, TARGET_TIMESTAMP, 1);

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        PriceInfo memory priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.Initialize, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateDeposit, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateWithdrawal, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateOpenPosition, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateClosePosition, "");
    }

    /**
     * @custom:scenario The user doesn't send the right amount of ether when validating a price
     * @custom:given The user validates a price that requires 1 wei of ether
     * @custom:when The user sends 0 ether as value in the `parseAndValidatePrice` call
     * @custom:or The user sends 2 wei as value in the `parseAndValidatePrice` call
     * @custom:or The user sends 1 wei as value with empty data in the `parseAndValidatePrice` call
     * @custom:then The function reverts with `OracleMiddlewareIncorrectFee`
     */
    function test_RevertWhen_parseAndValidatePriceIncorrectFee() public {
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateDeposit);
        bytes4 errorSelector = OracleMiddlewareIncorrectFee.selector;
        // Sanity check
        assertGt(validationCost, 0, "The validation cost must be higher than 0");

        // Fee too low
        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: validationCost - 1 }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Fee too high
        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: validationCost + 1 }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // No fee required if there's no data
        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.InitiateDeposit, ""
        );

        // No fee required if the validation timestamp is after the low latency delay
        bytes memory roundIdData = abi.encode(1);

        skip(LOW_LATENCY_DELAY + 1);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateDeposit, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateWithdrawal, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateOpenPosition, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, Types.ProtocolAction.ValidateClosePosition, roundIdData
        );
    }
}
