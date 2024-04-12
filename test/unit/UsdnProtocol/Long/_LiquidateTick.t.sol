// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { IOrderManager } from "src/interfaces/OrderManager/IOrderManager.sol";
import { ProtocolAction, LiquidationEffects } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test the _liquidateTick internal function of the long layer
 * @custom:background Given an instantiated protocol with an order manager set
 */
contract TestUsdnProtocolLongLiquidateTick is UsdnProtocolBaseFixture {
    int24 _tick;
    uint256 _tickVersion;
    bytes32 _tickHash;
    uint128 _liqPrice;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableOrderManager = true;
        super._setUp(params);

        wstETH.mintAndApprove(address(this), 1 ether, address(orderManager), type(uint256).max);

        // Create a long position to liquidate
        uint128 price = 2000 ether;
        int24 desiredLiqTick = protocol.getEffectiveTickForPrice(price - 200 ether);
        _liqPrice = protocol.getEffectivePriceForTick(desiredLiqTick);
        (_tick, _tickVersion,) =
            setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, _liqPrice, price);

        _tickHash = protocol.tickHash(_tick, _tickVersion);
    }

    function test_liquidateTickWithOrderManagerNotSet() public {
        vm.prank(ADMIN);
        protocol.setOrderManager(IOrderManager(address(0)));

        uint256 totalExpoInTick = protocol.getTotalExpoByTick(_tick);
        int256 tickValue = protocol.i_tickValue(_liqPrice, _tick, totalExpoInTick);
        LiquidationEffects memory effects = protocol.i_liquidateTick(_tick, _tickHash, _liqPrice);

        assertEq(effects.liquidatedPositions, 1, "One position should have been liquidated");
        assertEq(effects.remainingCollateral, tickValue, "The collateral remaining should equal the tick value");
        assertEq(effects.amountAddedToLong, 0, "No amount should have been added to long as no orders was processed");
    }
}
