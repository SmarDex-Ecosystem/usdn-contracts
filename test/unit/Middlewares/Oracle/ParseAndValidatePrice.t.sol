// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import {
    ETH_CONF,
    ETH_DECIMALS,
    ETH_PRICE,
    MOCK_PYTH_DATA,
    REDSTONE_ETH_DATA,
    REDSTONE_ETH_PRICE,
    REDSTONE_ETH_TIMESTAMP
} from "../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";
import { IMockPythError } from "../utils/MockPyth.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
    uint128 internal immutable REDSTONE_PENALTY;

    constructor() {
        super.setUp();

        FORMATTED_ETH_PRICE = (ETH_PRICE * (10 ** oracleMiddleware.getDecimals())) / 10 ** ETH_DECIMALS;
        FORMATTED_ETH_CONF = (ETH_CONF * (10 ** oracleMiddleware.getDecimals())) / 10 ** ETH_DECIMALS
            * oracleMiddleware.getConfRatioBps() / oracleMiddleware.BPS_DIVISOR();

        LOW_LATENCY_DELAY = uint128(oracleMiddleware.getLowLatencyDelay());
        TARGET_TIMESTAMP = uint128(block.timestamp);
        LIMIT_TIMESTAMP = TARGET_TIMESTAMP + LOW_LATENCY_DELAY;
        REDSTONE_PENALTY =
            uint128(REDSTONE_ETH_PRICE * oracleMiddleware.getPenaltyBps() / oracleMiddleware.BPS_DIVISOR());
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
            IUsdnProtocolTypes.ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
                value: oracleMiddleware.validationCost(MOCK_PYTH_DATA, action)
            }("", uint128(TARGET_TIMESTAMP - oracleMiddleware.getValidationDelay()), action, MOCK_PYTH_DATA);

            // Price + conf
            if (
                action == ProtocolAction.InitiateWithdrawal || action == ProtocolAction.ValidateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(price.price, FORMATTED_ETH_PRICE + FORMATTED_ETH_CONF, errorMessage);
            }
            // Price - conf
            else if (
                action == ProtocolAction.InitiateDeposit || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.InitiateClosePosition || action == ProtocolAction.ValidateClosePosition
            ) {
                assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, errorMessage);
            } else {
                assertEq(price.price, FORMATTED_ETH_PRICE, errorMessage);
            }
        }
    }

    /**
     * @custom:scenario Parse and validate price with Redstone
     * @custom:given ETH price is ~3838 USD in Redstone
     * @custom:and The validationDelay is respected
     * @custom:when Calling `parseAndValidatePrice` with a valid Redstone price update
     * @custom:then The price is adjusted according to the penalty
     */
    function test_parseAndValidatePriceWithRedstoneForAllActions() public {
        for (uint256 i; i < actions.length; i++) {
            IUsdnProtocolTypes.ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
                value: oracleMiddleware.validationCost(REDSTONE_ETH_DATA, action)
            }("", uint128(REDSTONE_ETH_TIMESTAMP - oracleMiddleware.getValidationDelay()), action, REDSTONE_ETH_DATA);

            // Price + conf
            if (
                action == ProtocolAction.InitiateWithdrawal || action == ProtocolAction.ValidateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(price.price, REDSTONE_ETH_PRICE + REDSTONE_PENALTY, errorMessage);
            }
            // Price - conf
            else if (
                action == ProtocolAction.InitiateDeposit || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.InitiateClosePosition || action == ProtocolAction.ValidateClosePosition
            ) {
                assertEq(price.price, REDSTONE_ETH_PRICE - REDSTONE_PENALTY, errorMessage);
            } else {
                assertEq(price.price, REDSTONE_ETH_PRICE, errorMessage);
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
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.Initialize, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateDeposit, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateWithdrawal, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateOpenPosition, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateClosePosition, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);
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

        PriceInfo memory priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, roundIdData);
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateWithdrawal, roundIdData);
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateOpenPosition, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateClosePosition, roundIdData
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
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateWithdrawal, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateOpenPosition, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateClosePosition, roundIdData);
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
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateWithdrawal, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateOpenPosition, roundIdData);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.ValidateClosePosition, roundIdData);
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
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.None, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateWithdrawal, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateOpenPosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateClosePosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );

        /* --------------------- Initiate actions revert as well -------------------- */

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateDeposit, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateWithdrawal, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateOpenPosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateClosePosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Initialize, MOCK_PYTH_DATA
        );

        /* --------------------- Validate actions revert as well -------------------- */

        bytes memory roundIdData = abi.encode(1);
        mockChainlinkOnChain.setRoundTimestamp(0, LIMIT_TIMESTAMP);
        mockChainlinkOnChain.setRoundTimestamp(1, LIMIT_TIMESTAMP + 1);
        mockChainlinkOnChain.setRoundPrice(0, -1);

        skip(LOW_LATENCY_DELAY + 1);

        // wrong previous roundId price

        validationCost = oracleMiddleware.validationCost(roundIdData, ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateWithdrawal, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateOpenPosition, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateClosePosition, roundIdData
        );

        // wrong validate roundId price

        mockChainlinkOnChain.setRoundPrice(0, int256(ETH_PRICE));
        mockChainlinkOnChain.setRoundPrice(1, -1);

        validationCost = oracleMiddleware.validationCost(roundIdData, ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateWithdrawal, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateOpenPosition, roundIdData
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateClosePosition, roundIdData
        );
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
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.None, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateWithdrawal, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateOpenPosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateClosePosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );

        /* ---------- Initiate actions revert if data provided is not empty --------- */

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateDeposit, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateWithdrawal, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateOpenPosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateClosePosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Initialize, MOCK_PYTH_DATA
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
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.None, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateWithdrawal, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateOpenPosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateClosePosition, MOCK_PYTH_DATA
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );

        /* ------------------ All initiate actions revert as well ------------------ */

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Initialize, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateDeposit, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateWithdrawal, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateOpenPosition, MOCK_PYTH_DATA
        );

        validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateClosePosition, MOCK_PYTH_DATA
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

        uint256 validationCost = oracleMiddleware.validationCost("", ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        PriceInfo memory priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Initialize, ""
        );

        validationCost = oracleMiddleware.validationCost("", ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateDeposit, ""
        );

        validationCost = oracleMiddleware.validationCost("", ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateWithdrawal, ""
        );

        validationCost = oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateOpenPosition, ""
        );

        validationCost = oracleMiddleware.validationCost("", ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, tooOldTimestamp));
        priceInfo = oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateClosePosition, ""
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
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.Initialize, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo = oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateDeposit, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo = oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateWithdrawal, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateOpenPosition, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", TARGET_TIMESTAMP, ProtocolAction.InitiateClosePosition, "");
    }

    /**
     * @custom:scenario Validate a price with Redstone but the chainlink price is way less
     * @custom:given The chainlink price is less than a third of the redstone price
     * @custom:when The `parseAndValidatePrice` function is called with valid redstone data
     * @custom:then The middleware reverts with `OracleMiddlewareRedstoneSafeguard`
     */
    function test_RevertWhen_parseAndValidatePriceWithRedstoneMoreThanChainlink() public {
        // set chainlink to a price that is less than a third of the redstone price (chainlink has 8 decimals)
        // to account for the penalty applied on redstone, we subtract a bit more than the penalty
        int256 mockedChainlinkPrice = int256((REDSTONE_ETH_PRICE - REDSTONE_PENALTY) / 3 / 1e10 - 1);
        mockChainlinkOnChain.setLatestRoundData(1, mockedChainlinkPrice, REDSTONE_ETH_TIMESTAMP, 1);
        uint256 validationDelay = oracleMiddleware.getValidationDelay();

        for (uint256 i; i < actions.length; i++) {
            IUsdnProtocolTypes.ProtocolAction action = actions[i];
            uint256 validationCost = oracleMiddleware.validationCost(REDSTONE_ETH_DATA, action);

            vm.expectRevert(OracleMiddlewareRedstoneSafeguard.selector);
            oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                "", uint128(REDSTONE_ETH_TIMESTAMP - validationDelay), action, REDSTONE_ETH_DATA
            );
        }
    }

    /**
     * @custom:scenario Validate a price with Redstone but the chainlink price is way more
     * @custom:given The chainlink price is more than thrice the redstone price
     * @custom:when The `parseAndValidatePrice` function is called with valid redstone data
     * @custom:then The middleware reverts with `OracleMiddlewareRedstoneSafeguard`
     */
    function test_RevertWhen_parseAndValidatePriceWithRedstoneLessThanChainlink() public {
        // set chainlink to a price that is more than thrice the redstone price (chainlink has 8 decimals)
        // to account for the penalty applied on redstone, we add a bit more than the penalty
        int256 mockedChainlinkPrice = int256(REDSTONE_ETH_PRICE + REDSTONE_PENALTY * 3 / 1e10 + 1);
        mockChainlinkOnChain.setLatestRoundData(1, mockedChainlinkPrice, REDSTONE_ETH_TIMESTAMP, 1);
        uint256 validationDelay = oracleMiddleware.getValidationDelay();

        for (uint256 i; i < actions.length; i++) {
            IUsdnProtocolTypes.ProtocolAction action = actions[i];
            uint256 validationCost = oracleMiddleware.validationCost(REDSTONE_ETH_DATA, action);

            vm.expectRevert(OracleMiddlewareRedstoneSafeguard.selector);
            oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                "", uint128(REDSTONE_ETH_TIMESTAMP - validationDelay), action, REDSTONE_ETH_DATA
            );
        }
    }

    /**
     * @custom:scenario Validate a price with Redstone but the price is zero
     * @custom:given The Redstone price is zero
     * @custom:when The `parseAndValidatePrice` function is called with mocked Redstone data with price zero
     * @custom:then The middleware reverts with `OracleMiddlewareWrongPrice`
     */
    function test_RevertWhen_parseAndValidatePriceWithRedstoneZeroPrice() public {
        oracleMiddleware.setMockRedstonePriceZero(true);
        uint256 validationDelay = oracleMiddleware.getValidationDelay();

        for (uint256 i; i < actions.length; i++) {
            IUsdnProtocolTypes.ProtocolAction action = actions[i];
            uint256 validationCost = oracleMiddleware.validationCost(REDSTONE_ETH_DATA, action);

            vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, 0));
            oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                "", uint128(REDSTONE_ETH_TIMESTAMP - validationDelay), action, REDSTONE_ETH_DATA
            );
        }
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
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);
        bytes4 errorSelector = OracleMiddlewareIncorrectFee.selector;
        // Sanity check
        assertGt(validationCost, 0, "The validation cost must be higher than 0");

        // Fee too low
        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: validationCost - 1 }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // Fee too high
        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: validationCost + 1 }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA
        );

        // No fee required if there's no data
        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }("", TARGET_TIMESTAMP, ProtocolAction.InitiateDeposit, "");

        // No fee required if the validation timestamp is after the low latency delay
        bytes memory roundIdData = abi.encode(1);

        skip(LOW_LATENCY_DELAY + 1);

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateDeposit, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateWithdrawal, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateOpenPosition, roundIdData
        );

        vm.expectRevert(errorSelector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", TARGET_TIMESTAMP, ProtocolAction.ValidateClosePosition, roundIdData
        );
    }
}
