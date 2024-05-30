// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";
import { ETH_PRICE, ETH_CONF, ETH_DECIMALS } from "test/unit/Middlewares/utils/Constants.sol";
import { IMockPythError } from "test/unit/Middlewares/utils/MockPyth.sol";

import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestOracleMiddlewareParseAndValidatePrice is OracleMiddlewareBaseFixture, IMockPythError {
    using Strings for uint256;

    uint256 internal immutable FORMATTED_ETH_PRICE;
    uint256 internal immutable FORMATTED_ETH_CONF;

    constructor() {
        super.setUp();

        FORMATTED_ETH_PRICE = (ETH_PRICE * (10 ** oracleMiddleware.getDecimals())) / 10 ** ETH_DECIMALS;
        FORMATTED_ETH_CONF = (ETH_CONF * (10 ** oracleMiddleware.getDecimals())) / 10 ** ETH_DECIMALS
            * oracleMiddleware.getConfRatioBps() / oracleMiddleware.BPS_DIVISOR();
    }

    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                             Unsupported action                             */
    /* -------------------------------------------------------------------------- */

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
                uint128(block.timestamp - oracleMiddleware.getValidationDelay()),
                11,
                abi.encode("data")
            )
        );

        assertEq(success, false, "Function should revert");
        assertEq(data.length, 0, "Function should revert");
    }

    /* -------------------------------------------------------------------------- */
    /*                               ETH is 2000 USD                              */
    /* -------------------------------------------------------------------------- */

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
        mockChainlinkOnChain.setLatestRoundData(1, mockedChainlinkPrice, block.timestamp, 1);

        for (uint256 i; i < actions.length; i++) {
            ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
                value: oracleMiddleware.validationCost(abi.encode("data"), action)
            }("", uint128(block.timestamp - oracleMiddleware.getValidationDelay()), action, abi.encode("data"));

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
     * @custom:scenario Parse and validate price for "initiate" actions using chainlink when empty data is provided
     * @custom:given Empty data is provided
     * @custom:when Calling parseAndValidatePrice for "initiate" actions
     * @custom:then It returns the onchain price from chainlink
     */
    function test_getPriceFromChainlinkWhenEmptyDataIsProvided() public {
        // Give a slightly different price for chainlink to be able to differentiate the oracles responses
        int256 mockedChainlinkPrice = int256(ETH_PRICE - 1);
        uint256 mockedChainlinkFormattedPrice = FORMATTED_ETH_PRICE - 1e10;
        mockChainlinkOnChain.setLatestRoundData(1, mockedChainlinkPrice, block.timestamp, 1);

        PriceInfo memory priceInfo =
            oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.Initialize, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateWithdrawal, "");
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateOpenPosition, ""
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateClosePosition, ""
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);
    }

    /**
     * @custom:scenario Parse and validate price for "validate" actions using chainlink with roundId data
     * @custom:given The chainlink target roundId data is provided
     * @custom:and The next chainlink roundId is provided
     * @custom:when Calling parseAndValidatePrice for "validate" actions after waiting the proper delay
     * @custom:then It returns the onchain price from chainlink
     */
    function test_getPriceFromChainlinkWhitRoundId() public {
        uint128 targetTimestamp = uint128(block.timestamp);
        uint128 earlyTimestamp = targetTimestamp + 20 minutes + 1;

        mockChainlinkOnChain.setRoundTimestamp(0, targetTimestamp);
        mockChainlinkOnChain.setRoundTimestamp(1, earlyTimestamp);
        (, int256 mockedChainlinkPrice,,,) = mockChainlinkOnChain.getRoundData(0);
        uint256 mockedChainlinkFormattedPrice =
            uint256(mockedChainlinkPrice) * 10 ** (oracleMiddleware.getDecimals() - mockChainlinkOnChain.decimals());
        bytes memory roundIdData = abi.encode(uint80(0));
        skip(1 days);

        PriceInfo memory priceInfo =
            oracleMiddleware.parseAndValidatePrice("", targetTimestamp, ProtocolAction.ValidateDeposit, roundIdData);
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", targetTimestamp, ProtocolAction.ValidateWithdrawal, roundIdData);
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", targetTimestamp, ProtocolAction.ValidateOpenPosition, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);

        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", targetTimestamp, ProtocolAction.ValidateClosePosition, roundIdData
        );
        assertEq(priceInfo.price, mockedChainlinkFormattedPrice);
    }

    /* -------------------------------------------------------------------------- */
    /*                        ETH is -1 USD in pyth oracle                        */
    /* -------------------------------------------------------------------------- */

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
        uint256 timestamp = block.timestamp - oracleMiddleware.getValidationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.None, abi.encode("data")
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateWithdrawal, abi.encode("data")
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateOpenPosition, abi.encode("data")
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateClosePosition, abi.encode("data")
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Liquidation, abi.encode("data")
        );

        /* --------------------- Initiate actions revert as well -------------------- */

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateWithdrawal, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateOpenPosition, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateClosePosition, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Initialize, abi.encode("data")
        );

        /* --------------------- Validate actions revert as well -------------------- */

        uint128 targetTimestamp = uint128(block.timestamp);
        mockChainlinkOnChain.setRoundPrice(1, -1);

        skip(1 days);

        validationCost = oracleMiddleware.validationCost(abi.encode(1), ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", targetTimestamp, ProtocolAction.ValidateDeposit, abi.encode(0)
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", targetTimestamp, ProtocolAction.ValidateWithdrawal, abi.encode(0)
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", targetTimestamp, ProtocolAction.ValidateOpenPosition, abi.encode(0)
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", targetTimestamp, ProtocolAction.ValidateClosePosition, abi.encode(0)
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              Pyth call revert                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price
     * @custom:given Pyth oracle reverts
     * @custom:and The validationDelay is respected
     * @custom:then It reverts when validating price for all action using Pyth oracle
     */
    function test_RevertWhen_parseAndValidatePriceWhileOracleMiddlewarePythValidationFailed() public {
        // Update price to -1 USD in pyth oracle
        mockPyth.toggleRevert();
        uint256 timestamp = block.timestamp - oracleMiddleware.getValidationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.None, abi.encode("data")
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateWithdrawal, abi.encode("data")
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateOpenPosition, abi.encode("data")
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateClosePosition, abi.encode("data")
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Liquidation, abi.encode("data")
        );

        /* ---------- Initiate actions revert if data provided is not empty --------- */

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateWithdrawal, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateOpenPosition, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateClosePosition, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Initialize, abi.encode("data")
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

        uint256 timestamp = block.timestamp - oracleMiddleware.getValidationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.None, abi.encode("data")
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateWithdrawal, abi.encode("data")
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateOpenPosition, abi.encode("data")
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.ValidateClosePosition, abi.encode("data")
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Liquidation, abi.encode("data")
        );

        /* ------------------ All initiate actions revert as well ------------------ */

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.Initialize, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateWithdrawal, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateOpenPosition, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(timestamp), ProtocolAction.InitiateClosePosition, abi.encode("data")
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                           Chainlink call reverts                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price for "Initiate" actions fails when no data is provided and chainlink's
     * data is too old
     * @custom:given Chainlink oracle's data's timestamp is too old
     * @custom:and Empty data has been provided
     * @custom:then It reverts with a OracleMiddlewarePriceTooOld error
     */
    function test_RevertWhen_ChainlinkPriceIsTooOld() public {
        uint256 timestamp = block.timestamp - oracleMiddleware.getChainlinkTimeElapsedLimit();
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
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        mockChainlinkOnChain.setLatestRoundData(1, -1, block.timestamp, 1);

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        PriceInfo memory priceInfo =
            oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.Initialize, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo =
            oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateWithdrawal, "");

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateOpenPosition, ""
        );

        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1 * 1e10));
        priceInfo = oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateClosePosition, ""
        );
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
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);

        // Sanity check
        assertGt(validationCost, 0, "The validation cost must be higher than 0");

        // Fee too low
        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.parseAndValidatePrice{ value: validationCost - 1 }(
            "", uint128(block.timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // Fee too high
        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.parseAndValidatePrice{ value: validationCost + 1 }(
            "", uint128(block.timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // No fee required if there's no data
        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", uint128(block.timestamp), ProtocolAction.InitiateDeposit, ""
        );

        skip(20 minutes + 1);

        // No fee required if data length above the limit
        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", uint128(block.timestamp - (20 minutes + 1)), ProtocolAction.ValidateDeposit, abi.encode(0)
        );

        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", uint128(block.timestamp - (20 minutes + 1)), ProtocolAction.ValidateWithdrawal, abi.encode(0)
        );

        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", uint128(block.timestamp - (20 minutes + 1)), ProtocolAction.ValidateOpenPosition, abi.encode(0)
        );

        vm.expectRevert(OracleMiddlewareIncorrectFee.selector);
        oracleMiddleware.parseAndValidatePrice{ value: 1 }(
            "", uint128(block.timestamp - (20 minutes + 1)), ProtocolAction.ValidateClosePosition, abi.encode(0)
        );
    }
}
