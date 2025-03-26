// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { ETH_CONF, ETH_DECIMALS, ETH_PRICE, MOCK_PYTH_DATA } from "../utils/Constants.sol";
import { WusdnToEthBaseFixture } from "../utils/Fixtures.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `parseAndValidatePrice` function of `WusdnToEthOracleMiddlewareWithPyth`
 * @custom:background Given the price ETH is 2000 USD
 * @custom:and The confidence interval is 20 USD
 * @custom:and The USDN divisor is 9e17
 */
contract TestWusdnToEthOracleParseAndValidatePrice is WusdnToEthBaseFixture {
    using Strings for uint256;

    uint256 internal immutable FORMATTED_ETH_PRICE;
    uint256 internal immutable FORMATTED_ETH_CONF;
    uint256 internal immutable ETH_CONF_RATIO;
    uint256 internal immutable USDN_DIVISOR;

    constructor() {
        super.setUp();

        FORMATTED_ETH_PRICE = ETH_PRICE * 10 ** middleware.getDecimals() / 10 ** ETH_DECIMALS;
        FORMATTED_ETH_CONF = ETH_CONF * 10 ** middleware.getDecimals() / 10 ** ETH_DECIMALS;
        ETH_CONF_RATIO = FORMATTED_ETH_CONF * middleware.getConfRatioBps() / middleware.BPS_DIVISOR();
        USDN_DIVISOR = usdn.divisor();
    }

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Parse and validate the neutral price
     * @custom:given ETH price is 2000 USD and estimated WUSDN price is $1.111111... ($1/0.9)
     * @custom:when The price is retrieved
     * @custom:then The price is 0.000555555555555555 ETH/WUSDN
     */
    function test_parseAndValidatePriceNeutral() public {
        PriceInfo memory price = middleware.parseAndValidatePrice{
            value: middleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Liquidation)
        }("", uint128(block.timestamp), Types.ProtocolAction.Liquidation, MOCK_PYTH_DATA);
        assertEq(price.price, 0.000555555555555555 ether, "neutral price");
    }

    /**
     * @custom:scenario Parse and validate the price
     * @custom:given ETH price is 2000 USD in pyth and chainlink oracles
     * @custom:and The validationDelay is respected
     * @custom:when The Protocol action is any action
     * @custom:then The price is exactly 2000 USD
     */
    function test_parseAndValidatePriceForAllActions() public {
        for (uint256 i; i < actions.length; i++) {
            Types.ProtocolAction action = actions[i];
            string memory errorMessage =
                string.concat("Wrong short oracle middleware price for action: ", uint256(action).toString());

            uint128 timestamp = uint128(block.timestamp);
            if (action != Types.ProtocolAction.Liquidation) {
                timestamp -= uint128(middleware.getValidationDelay());
            }

            PriceInfo memory price = middleware.parseAndValidatePrice{
                value: middleware.validationCost(MOCK_PYTH_DATA, action)
            }("", timestamp, action, MOCK_PYTH_DATA);

            uint256 neutralPrice = _calcPrice(FORMATTED_ETH_PRICE);

            // ETH Price - conf (inverse from "long" oracles)
            // but the final price is higher than neutral price
            if (
                action == Types.ProtocolAction.ValidateWithdrawal || action == Types.ProtocolAction.ValidateOpenPosition
            ) {
                assertEq(price.price, _calcPrice(FORMATTED_ETH_PRICE - ETH_CONF_RATIO), errorMessage);
                assertGt(price.price, neutralPrice, "price should be greater than neutral price");
            }
            // ETH Price + conf (inverse from "long" oracles)
            // but the final price is lower than neutral price
            else if (
                action == Types.ProtocolAction.ValidateDeposit || action == Types.ProtocolAction.ValidateClosePosition
            ) {
                assertEq(price.price, _calcPrice(FORMATTED_ETH_PRICE + ETH_CONF_RATIO), errorMessage);
                assertLt(price.price, neutralPrice, "price should be smaller than neutral price");
            } else {
                assertEq(price.price, neutralPrice, errorMessage);
            }
        }
    }

    function _calcPrice(uint256 ethPrice) internal view returns (uint256) {
        return 1e54 / (ethPrice * USDN_DIVISOR);
    }
}
