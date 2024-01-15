// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/OracleMiddleware/utils/Fixtures.sol";
import { ETH_PRICE, ETH_CONF } from "test/unit/OracleMiddleware/utils/Constants.sol";

import { PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @custom:feature The `validationCost` function of `OracleMiddleware`
 */
contract TestOracleMiddlewareValidationCost is OracleMiddlewareBaseFixture {
    bytes[] public data;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is a value that is not supported
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_validationCostForUnsupportedAction() public {
        (bool success, bytes memory _data) = address(oracleMiddleware).call(
            abi.encodeWithSelector(oracleMiddleware.validationCost.selector, abi.encode("data"), 11)
        );

        assertEq(success, false, "Function should revert");
        assertEq(_data.length, 0, "Function should revert");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'None'
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_parseAndValidatePrice() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.None);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost for None action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'Initialize'
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_validationCostForInitializeAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Initialize);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost for Initialize action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'InitiateDeposit'
     * @custom:then Te validation cost is 0 because it use chainlink onchain
     */
    function test_validationCostForInitiateDepositAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateDeposit);

        assertEq(fee, 0, "Wrong fee cost for InitiateDeposit action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'ValidateDeposit'
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_validationCostForValidateDepositAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateDeposit);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost for ValidateDeposit action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'InitiateWithdrawal'
     * @custom:then Te validation cost is 0 because it use chainlink onchain
     */
    function test_validationCostForInitiateWithdrawalAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateWithdrawal);

        assertEq(fee, 0, "Wrong fee cost for InitiateWithdrawal action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'ValidateWithdrawal'
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_validationCostForValidateWithdrawalAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateWithdrawal);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost for ValidateWithdrawal action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'Initialize'
     * @custom:then Te validation cost is 0 because it use chainlink onchain
     */
    function test_validationCostForInitiateOpenPositionAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateOpenPosition);

        assertEq(fee, 0, "Wrong fee cost for InitiateOpenPosition action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'ValidateOpenPosition'
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_validationCostForValidateOpenPositionAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateOpenPosition);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost for ValidateOpenPosition action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'InitiateClosePosition'
     * @custom:then Te validation cost is 0 because it use chainlink onchain
     */
    function test_validationCostForInitiateClosePositionAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.InitiateClosePosition);

        assertEq(fee, 0, "Wrong fee cost for InitiateClosePosition action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'ValidateClosePosition'
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_validationCostForValidateClosePositionAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.ValidateClosePosition);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost for ValidateClosePosition action");
    }

    /**
     * @custom:scenario Call `validationCost` function
     * @custom:when Protocol action is 'Liquidation'
     * @custom:then Te validation cost is the same as pythOracle
     */
    function test_validationCostForLiquidationAction() public {
        uint256 fee = oracleMiddleware.validationCost(abi.encode("data"), ProtocolAction.Liquidation);

        assertEq(fee, mockPyth.getUpdateFee(data), "Wrong fee cost for Liquidation action");
    }
}
