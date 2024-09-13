// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @custom:feature Test the _getOraclePrice internal function of the actions layer
 */
contract TestUsdnProtocolActionsGetOraclePrice is UsdnProtocolBaseFixture {
    using Strings for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        oracleMiddleware.setRequireValidationCost(true);
    }

    /**
     * @custom:scenario Validate price data with oracle middleware
     * @custom:given The oracle middleware requires 1 wei for validation
     * @custom:when The price is requested for each action (with the exact right amount or more)
     * @custom:then The price is returned and the validation cost is equal to 1 wei
     */
    function test_getOraclePrice() public {
        for (uint8 i = 0; i <= uint8(type(ProtocolAction).max); i++) {
            ProtocolAction action = ProtocolAction(i);
            uint128 currentPrice = 2000 ether;
            bytes memory priceData = abi.encode(currentPrice);
            uint256 fee = oracleMiddleware.validationCost(priceData, action);
            PriceInfo memory price =
                protocol.i_getOraclePrice{ value: fee }(action, block.timestamp - 30 minutes, hex"beef", priceData);
            assertEq(price.price, currentPrice, string.concat("wrong price for action", uint256(i).toString()));
            assertEq(oracleMiddleware.lastActionId(), hex"beef", "action ID");

            // sending more should not revert either
            // (refund is handled outside of this function and is tested separately)
            protocol.i_getOraclePrice{ value: fee * 2 }(action, block.timestamp - 30 minutes, "", priceData);
        }
    }

    /**
     * @custom:scenario Validate price data but insufficient fee provided
     * @custom:given The oracle middleware requires 1 wei for validation
     * @custom:when The price is requested for each action (without providing ether)
     * @custom:then The function reverts with the `UsdnProtocolInsufficientOracleFee` error
     */
    function test_RevertWhen_getOraclePriceInsufficientFee() public {
        for (uint8 i = 0; i <= uint8(type(ProtocolAction).max); i++) {
            ProtocolAction action = ProtocolAction(i);
            uint128 currentPrice = 2000 ether;
            bytes memory priceData = abi.encode(currentPrice);
            vm.expectRevert(UsdnProtocolInsufficientOracleFee.selector);
            protocol.i_getOraclePrice(action, block.timestamp, hex"beef", priceData);
        }
    }

    /**
     * @custom:scenario Try to call a paused `_getOraclePrice` function
     * @custom:when The function is called
     * @custom:then The transaction reverts with `UsdnProtocolFunctionPaused`
     */
    function test_RevertWhen_getOraclePricePaused() public {
        vm.prank(ADMIN);
        protocol.setOraclePricePaused(true);
        vm.expectRevert(UsdnProtocolFunctionPaused.selector);
        protocol.i_getOraclePrice(ProtocolAction.None, block.timestamp, "", "");
    }
}
