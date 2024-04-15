// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The _checkSafetyMargin internal function of the UsdnProtocolLong contract.
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x
 */
contract TestUsdnProtocolLongCheckSafetyMargin is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 10 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Call `_checkSafetyMargin` reverts when the liquidationPriceLimit is
     * too high compare to currentPrice
     * @custom:when The value of liquidationPriceLimit is bigger than the maxLiquidationPrice calculated
     * @custom:then It reverts with a UsdnProtocolLiquidationPriceSafetyMargin error
     */
    function test_RevertWhen_setLiquidationPriceWithoutSafetyMarginBps() public {
        uint128 currentPrice = 100 ether;
        uint128 liquidationPriceLimit = 98 ether;
        uint128 bps_divisor = (protocol.BPS_DIVISOR()).toUint128();
        uint128 maxLiquidationPrice =
            (currentPrice * (bps_divisor - protocol.getSafetyMarginBps()) / bps_divisor).toUint128();

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolLiquidationPriceSafetyMargin.selector, liquidationPriceLimit, maxLiquidationPrice
            )
        );
        protocol.i_checkSafetyMargin(currentPrice, liquidationPriceLimit);
    }
    /**
     * @custom:scenario Call `_checkSafetyMargin` reverts when the liquidationPriceLimit is
     * too high compare to currentPrice
     * @custom:when The value of liquidationPriceLimit is bigger than the maxLiquidationPrice calculated
     * @custom:then It reverts with a UsdnProtocolLiquidationPriceSafetyMargin error
     */

    function test_setLiquidationPriceWithoutSafetyMarginBps() public {
        uint128 currentPrice = 100 ether;
        uint128 liquidationPriceLimit = 98 ether;
        uint128 bps_divisor = (protocol.BPS_DIVISOR()).toUint128();
        uint128 maxLiquidationPrice =
            (currentPrice * (bps_divisor - protocol.getSafetyMarginBps()) / bps_divisor).toUint128();

        vm.expectRevert(
            abi.encodeWithSelector(
                UsdnProtocolLiquidationPriceSafetyMargin.selector, liquidationPriceLimit, maxLiquidationPrice
            )
        );
        protocol.i_checkSafetyMargin(currentPrice, liquidationPriceLimit);
    }
}
