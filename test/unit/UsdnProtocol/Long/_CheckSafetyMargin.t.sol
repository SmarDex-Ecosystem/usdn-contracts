// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolConstantsLibrary as Constant } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The _checkSafetyMargin internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongCheckSafetyMargin is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Call `_checkSafetyMargin` reverts when the liquidationPrice is greater than the
     * maxLiquidationPrice
     * @custom:given The current price is 100 ether
     * @custom:and The liquidationPrice is 98 ether
     * @custom:when The value of liquidationPrice is greater than the maxLiquidationPrice calculated
     * @custom:then It reverts with a UsdnProtocolLiquidationPriceSafetyMargin error
     */
    function test_RevertWhen_setLiquidationPriceWithoutSafetyMarginBps() public {
        uint128 currentPrice = 100 ether;
        uint128 liquidationPrice = 98 ether;
        uint128 bpsDivisor = (Constant.BPS_DIVISOR).toUint128();
        uint128 maxLiquidationPrice =
            (currentPrice * (bpsDivisor - protocol.getSafetyMarginBps()) / bpsDivisor).toUint128();

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolLiquidationPriceSafetyMargin.selector, liquidationPrice, maxLiquidationPrice
            )
        );
        protocol.i_checkSafetyMargin(currentPrice, liquidationPrice);
    }

    /**
     * @custom:scenario Call `_checkSafetyMargin` with a liquidationPrice that is lower than the
     * maxLiquidationPrice
     * @custom:given The current price is 100 ether
     * @custom:and The liquidationPrice is 98 ether - 1
     * @custom:when The value of liquidationPrice is lower than the maxLiquidationPrice calculated
     * @custom:then It does not revert
     */
    function test_setLiquidationPriceOverTheLimit() public view {
        uint128 currentPrice = 100 ether;
        uint128 liquidationPrice = 98 ether - 1;

        protocol.i_checkSafetyMargin(currentPrice, liquidationPrice);
    }
}
