// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { ETH_PRICE, ETH_CONF } from "test/unit/OracleMiddleware/utils/Constants.sol";
import { IMockPythError } from "test/unit/OracleMiddleware/utils/MockPyth.sol";

import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestOracleMiddlewareParseAndValidatePrice is
    OracleMiddlewareBaseFixture,
    IOracleMiddlewareErrors,
    IMockPythError
{
    using Strings for uint256;

    uint256 internal immutable FORMATTED_ETH_PRICE;
    uint256 internal immutable FORMATTED_ETH_CONF;

    constructor() {
        super.setUp();

        FORMATTED_ETH_PRICE =
            (ETH_PRICE * (10 ** oracleMiddleware.decimals())) / (10 ** oracleMiddleware.pythDecimals());
        FORMATTED_ETH_CONF = (ETH_CONF * (10 ** oracleMiddleware.decimals())) / (10 ** oracleMiddleware.pythDecimals());
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
     * @custom:then The price is exactly 2000 USD
     */
    function test_RevertWhen_parseAndValidatePriceWithUnsupportedAction() public {
        (bool success, bytes memory data) = address(oracleMiddleware).call(
            abi.encodeWithSelector(
                oracleMiddleware.parseAndValidatePrice.selector,
                uint128(block.timestamp - oracleMiddleware.validationDelay()),
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
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when Protocol action is "None"
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForAllActions() public {
        for (uint256 i; i < actions.length; i++) {
            ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
                value: oracleMiddleware.validationCost(abi.encode("data"), action)
            }(uint128(block.timestamp - oracleMiddleware.validationDelay()), action, abi.encode("data"));

            // Price + conf
            if (action == ProtocolAction.ValidateOpenPosition) {
                assertEq(price.price, FORMATTED_ETH_PRICE + FORMATTED_ETH_CONF, errorMessage);
            }
            // Price - conf
            else if (
                action == ProtocolAction.ValidateClosePosition || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.Liquidation
            ) {
                assertEq(price.price, FORMATTED_ETH_PRICE - FORMATTED_ETH_CONF, errorMessage);
            } else {
                assertEq(price.price, FORMATTED_ETH_PRICE, errorMessage);
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                        ETH is -1 USD in pyth oracle                        */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price
     * @custom:given ETH price is -1 USD in pyth oracle
     * @custom:and The validationDelay is respected
     * @custom:then It reverts when validating price for all action using Pyth oracle
     */
    function test_RevertWhen_parseAndValidatePriceWithNegativeEthPrice() public {
        // Update price to -1 USD in pyth oracle
        mockPyth.updatePrice(-1);
        uint256 timestamp = block.timestamp - oracleMiddleware.validationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.None, abi.encode("data")
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateWithdrawal, abi.encode("data")
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateOpenPosition, abi.encode("data")
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateClosePosition, abi.encode("data")
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.Liquidation, abi.encode("data")
        );

        /* ---------------------- Initiates action still works ---------------------- */

        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit)
        }(uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data"));
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateDeposit action");

        PriceInfo memory price2 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateWithdrawal)
        }(uint128(timestamp), ProtocolAction.InitiateWithdrawal, abi.encode("data"));
        assertEq(price2.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateWithdrawal action");

        PriceInfo memory price3 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateOpenPosition)
        }(uint128(timestamp), ProtocolAction.InitiateOpenPosition, abi.encode("data"));
        assertEq(price3.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateOpenPosition action");

        PriceInfo memory price4 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateClosePosition)
        }(uint128(timestamp), ProtocolAction.InitiateClosePosition, abi.encode("data"));
        assertEq(price4.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateClosePosition action");

        PriceInfo memory price5 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Initialize)
        }(uint128(timestamp), ProtocolAction.Initialize, abi.encode("data"));
        assertEq(price5.price, FORMATTED_ETH_PRICE, "Wrong price for Initialize action");
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
        uint256 timestamp = block.timestamp - oracleMiddleware.validationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.None, abi.encode("data")
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateWithdrawal, abi.encode("data")
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateOpenPosition, abi.encode("data")
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateClosePosition, abi.encode("data")
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.Liquidation, abi.encode("data")
        );

        /* ---------------------- Initiates action still works ---------------------- */

        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit)
        }(uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data"));
        assertEq(price.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateDeposit action");

        PriceInfo memory price2 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateWithdrawal)
        }(uint128(timestamp), ProtocolAction.InitiateWithdrawal, abi.encode("data"));
        assertEq(price2.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateWithdrawal action");

        PriceInfo memory price3 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateOpenPosition)
        }(uint128(timestamp), ProtocolAction.InitiateOpenPosition, abi.encode("data"));
        assertEq(price3.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateOpenPosition action");

        PriceInfo memory price4 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateClosePosition)
        }(uint128(timestamp), ProtocolAction.InitiateClosePosition, abi.encode("data"));
        assertEq(price4.price, FORMATTED_ETH_PRICE, "Wrong price for InitiateClosePosition action");

        PriceInfo memory price5 = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Initialize)
        }(uint128(timestamp), ProtocolAction.Initialize, abi.encode("data"));
        assertEq(price5.price, FORMATTED_ETH_PRICE, "Wrong price for Initialize action");
    }

    /* -------------------------------------------------------------------------- */
    /*                      Pyth and chainlink calls reverts                      */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate price
     * @custom:given Pyth and chainlink oracle reverts
     * @custom:and The validationDelay is respected
     * @custom:then It reverts when validating price for all action using Pyth oracle
     */
    function test_RevertWhen_parseAndValidatePriceWhileAllValidationFailed() public {
        // Update price to -1 USD in oracles
        mockPyth.toggleRevert();
        mockChainlinkOnChain.toggleRevert();

        uint256 timestamp = block.timestamp - oracleMiddleware.validationDelay();

        // Expect revert when validating price for None action
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.None, abi.encode("data")
        );

        // Expect revert when validating price for ValidateDeposit action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateDeposit, abi.encode("data")
        );

        // Expect revert when validating price for ValidateWithdrawal action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateWithdrawal, abi.encode("data")
        );

        // Expect revert when validating price for ValidateOpenPosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateOpenPosition, abi.encode("data")
        );

        // Expect revert when validating price for ValidateClosePosition action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.ValidateClosePosition, abi.encode("data")
        );

        // Expect revert when validating price for Liquidation action
        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(MockedPythError.selector));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.Liquidation, abi.encode("data")
        );

        /* ---------------------- Initiates action still works ---------------------- */

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Initialize);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.Initialize, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateWithdrawal);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.InitiateWithdrawal, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.InitiateOpenPosition, abi.encode("data")
        );

        validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateClosePosition);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, -1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.InitiateClosePosition, abi.encode("data")
        );
    }

    function test_RevertWhen_chainlinkPriceIsTooOld() public {
        uint256 timestamp = block.timestamp - oracleMiddleware.validationDelay();

        /* ------------ Doesn't revert when the timestamp is not too old ------------ */

        mockChainlinkOnChain.updateLastPublishTime(block.timestamp - 1 minutes);
        oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit)
        }(uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data"));

        mockChainlinkOnChain.updateLastPublishTime(block.timestamp - 30 minutes);
        oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit)
        }(uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data"));

        mockChainlinkOnChain.updateLastPublishTime(block.timestamp - 59 minutes);
        oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit)
        }(uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data"));

        /* ------------------ Revert when the timestamp is too old ------------------ */

        mockChainlinkOnChain.updateLastPublishTime(block.timestamp - 3601 seconds);
        uint256 validationCost = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit);
        vm.expectRevert(
            abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, ETH_PRICE, block.timestamp - 3601 seconds)
        );
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data")
        );

        mockChainlinkOnChain.updateLastPublishTime(block.timestamp - 2 hours);
        vm.expectRevert(
            abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, ETH_PRICE, block.timestamp - 2 hours)
        );
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data")
        );

        mockChainlinkOnChain.updateLastPublishTime(0);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePriceTooOld.selector, ETH_PRICE, 0));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            uint128(timestamp), ProtocolAction.InitiateDeposit, abi.encode("data")
        );
    }
}
