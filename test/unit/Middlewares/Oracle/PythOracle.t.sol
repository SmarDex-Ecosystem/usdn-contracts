// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature The `PythOracle` specific functions
contract TestOracleMiddlewarePythOracle is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario The Pyth confidence interval, after scaling with `_confRatio`, is greater than the price.
     * @custom:given The price of the asset is $10 and the confidence interval is $30.
     * @custom:when The `parseAndValidatePrice` function is called with an action that uses the lower bound of the conf
     * interval.
     * @custom:then The price is adjusted to 1 wei to avoid being negative or zero.
     */
    function test_pythConfGreaterThanPrice() public {
        mockPyth.setPrice(10e8);
        mockPyth.setConf(30e8);

        // ValidateDeposit adjusts down with conf
        PriceInfo memory price = oracleMiddleware.parseAndValidatePrice{
            value: oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.ValidateDeposit)
        }("", uint128(block.timestamp), Types.ProtocolAction.ValidateDeposit, MOCK_PYTH_DATA);
        assertEq(price.price, 1, "price should be 1");
    }

    /**
     * @custom:scenario The Pyth exponent is a positive number
     * @custom:given The exponent is 1 (instead of -8)
     * @custom:when The `parseAndValidatePrice` function is called
     * @custom:then The function reverts with the error `OracleMiddlewarePythPositiveExponent`
     */
    function test_pythInvalidExponent() public {
        mockPyth.setExpo(1);
        uint256 validationCost = oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.Liquidation);
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewarePythPositiveExponent.selector, 1));
        oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            "", uint128(block.timestamp), Types.ProtocolAction.Liquidation, MOCK_PYTH_DATA
        );
    }
}
