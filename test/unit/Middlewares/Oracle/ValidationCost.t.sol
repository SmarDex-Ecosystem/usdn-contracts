// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `getValidationCost` function of `OracleMiddleware`
 */
contract TestOracleMiddlewareValidationCost is OracleMiddlewareBaseFixture {
    bytes[] public data;

    function setUp() public override {
        super.setUp();
        data.push(abi.encode("data"));
    }

    /**
     * @custom:scenario Call `getValidationCost` function
     * @custom:when Protocol action is a value that is not supported
     * @custom:then The validation cost is the same as pythOracle
     */
    function test_RevertWhen_validationCostWithUnsupportedAction() public {
        (bool success, bytes memory _data) = address(oracleMiddleware).call(
            abi.encodeWithSelector(oracleMiddleware.validationCost.selector, abi.encode("data"), 11)
        );

        assertEq(success, false, "Function should revert");
        assertEq(_data.length, 0, "Function should revert");
    }

    /**
     * @custom:scenario Call `getValidationCost` function
     * @custom:when Data is not empty
     * @custom:then The validation cost is the same as pythOracle
     */
    function test_parseAndValidatePriceWithData() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost when data is not empty");
    }

    /**
     * @custom:scenario Call `getValidationCost` function
     * @custom:when Data is empty
     * @custom:then The validation cost is the same as pythOracle
     */
    function test_parseAndValidatePriceWithoutData() public {
        uint256 fee = oracleMiddleware.validationCost("", ProtocolAction.None);

        assertEq(fee, 0, "Fee should be 0 when there's no data");
    }

    /**
     * @custom:scenario Call `getValidationCost` function
     * @custom:when Data is filled with a bytes length lower than the limit
     * @custom:then The validation cost is 0
     */
    function test_parseAndValidatePriceLowerThanLimit() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode(type(uint256).max), ProtocolAction.None);
        assertEq(fee, 0, "Validation should be 0 when data length is below the limit");
    }

    /**
     * @custom:scenario Call `getValidationCost` function
     * @custom:when Data is filled with a bytes length above than the limit
     * @custom:then The validation cost is higher than 0
     */
    function test_parseAndValidatePriceHigherThanLimit() public {
        uint256 fee =
            oracleMiddleware.validationCost(abi.encodePacked(type(uint256).max, type(uint8).max), ProtocolAction.None);
        assertGt(fee, 0, "Validation should be greater than 0 when data length is above the limit");
    }
}
