// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { WstethBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";
import { ETH_PRICE, ETH_CONF, ETH_DECIMALS } from "test/unit/Middlewares/utils/Constants.sol";

import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `WstethOracle`
 * @custom:background Given the price WSTETH is ~1739 USD
 * @custom:and The confidence interval is 20 USD
 */
contract TestWstethOracleParseAndValidatePrice is WstethBaseFixture {
    using Strings for uint256;

    uint256 internal immutable FORMATTED_ETH_PRICE;
    uint256 internal immutable FORMATTED_ETH_CONF;
    uint256 internal immutable ETH_CONF_RATIO;
    uint256 internal immutable ETH_PER_TOKEN;

    constructor() {
        super.setUp();

        FORMATTED_ETH_PRICE = ETH_PRICE * 10 ** wstethOracle.getDecimals() / 10 ** ETH_DECIMALS;
        FORMATTED_ETH_CONF = ETH_CONF * 10 ** wstethOracle.getDecimals() / 10 ** ETH_DECIMALS;
        ETH_CONF_RATIO = FORMATTED_ETH_CONF * wstethOracle.getConfRatioBps() / wstethOracle.BPS_DIVISOR();
        ETH_PER_TOKEN = wsteth.stEthPerToken();
    }

    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                               WSTETH is ~1739 USD                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Parse and validate the price
     * @custom:given WSTETH price is ~1739 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when The Protocol action is any action
     * @custom:then The price is exactly ~1739 USD
     */
    function test_parseAndValidatePriceForAllActions() public {
        for (uint256 i; i < actions.length; i++) {
            ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong wsteth oracle middleware price for action: ", uint256(action).toString());

            uint128 timestamp = uint128(block.timestamp);
            if (action != ProtocolAction.Liquidation) {
                timestamp -= uint128(wstethOracle.getValidationDelay());
            }

            PriceInfo memory price = wstethOracle.parseAndValidatePrice{
                value: wstethOracle.validationCost(abi.encode("data"), action)
            }("", timestamp, action, abi.encode("data"));

            // Price + conf
            if (
                action == ProtocolAction.InitiateWithdrawal || action == ProtocolAction.ValidateWithdrawal
                    || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(price.price, stethToWsteth(FORMATTED_ETH_PRICE + ETH_CONF_RATIO, ETH_PER_TOKEN), errorMessage);
            }
            // Price - conf
            else if (
                action == ProtocolAction.InitiateDeposit || action == ProtocolAction.ValidateDeposit
                    || action == ProtocolAction.InitiateClosePosition || action == ProtocolAction.ValidateClosePosition
            ) {
                assertEq(price.price, stethToWsteth(FORMATTED_ETH_PRICE - ETH_CONF_RATIO, ETH_PER_TOKEN), errorMessage);
            } else {
                assertEq(price.price, stethToWsteth(FORMATTED_ETH_PRICE, ETH_PER_TOKEN), errorMessage);
            }
        }
    }
}
