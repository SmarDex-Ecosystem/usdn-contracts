// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

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
import { OracleMiddlewareWithRedstoneFixture } from "../utils/Fixtures.sol";
import { IMockPythError } from "../utils/MockPyth.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `OracleMiddleware`
 * @custom:background Given the price of ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestOracleMiddlewareParseAndValidatePriceWithRedstone is
    OracleMiddlewareWithRedstoneFixture,
    IMockPythError
{
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
     * @custom:scenario Parse and validate price with Redstone
     * @custom:given ETH price is ~3838 USD in Redstone
     * @custom:and The validationDelay is respected
     * @custom:when Calling `parseAndValidatePrice` with a valid Redstone price update
     * @custom:then The price is adjusted according to the penalty
     */
    function test_parseAndValidatePriceWithRedstoneForAllActions() public {
        for (uint256 i; i < actions.length; i++) {
            Types.ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong oracle middleware price for action: ", uint256(action).toString());

            PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
                value: oracleMiddleware.validationCost(REDSTONE_ETH_DATA, action)
            }("", uint128(REDSTONE_ETH_TIMESTAMP - oracleMiddleware.getValidationDelay()), action, REDSTONE_ETH_DATA);

            // Price + conf
            if (
                action == Types.ProtocolAction.InitiateWithdrawal || action == Types.ProtocolAction.ValidateWithdrawal
                    || action == Types.ProtocolAction.InitiateOpenPosition
                    || action == Types.ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(price.price, REDSTONE_ETH_PRICE + REDSTONE_PENALTY, errorMessage);
            }
            // Price - conf
            else if (
                action == Types.ProtocolAction.InitiateDeposit || action == Types.ProtocolAction.ValidateDeposit
                    || action == Types.ProtocolAction.InitiateClosePosition
                    || action == Types.ProtocolAction.ValidateClosePosition
            ) {
                assertEq(price.price, REDSTONE_ETH_PRICE - REDSTONE_PENALTY, errorMessage);
            } else {
                assertEq(price.price, REDSTONE_ETH_PRICE, errorMessage);
            }
        }
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
            Types.ProtocolAction action = actions[i];
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
            Types.ProtocolAction action = actions[i];
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
            Types.ProtocolAction action = actions[i];
            uint256 validationCost = oracleMiddleware.validationCost(REDSTONE_ETH_DATA, action);

            vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareWrongPrice.selector, 0));
            oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
                "", uint128(REDSTONE_ETH_TIMESTAMP - validationDelay), action, REDSTONE_ETH_DATA
            );
        }
    }
}
