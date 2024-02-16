// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The open position function of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolOpenPosition is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mint(address(this), INITIAL_WSTETH_BALANCE);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario The user initiates an open position action
     * @custom:given The amount of collateral is 1 wstETH and the current price is 2000$
     * @custom:when The user initiates an open position with 1 wstETH and a desired liquidation price of 1333$ (approx
     * 3x leverage)
     * @custom:then The protocol creates the position and emits the InitiatedOpenPosition event
     */
    function test_initiateOpenPosition() public {
        uint96 longAmount = 1 ether;
        uint128 currentPrice = 2000 ether;
        bytes memory priceData = abi.encode(currentPrice);
        uint128 desiredLiqPrice = currentPrice * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);
        uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            expectedTick - int24(protocol.liquidationPenalty()) * protocol.tickSpacing()
        );
        uint128 expectedLeverage =
            uint128((10 ** protocol.LEVERAGE_DECIMALS() * currentPrice) / (currentPrice - liqPriceWithoutPenalty));

        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this), uint40(block.timestamp), expectedLeverage, longAmount, currentPrice, expectedTick, 0, 0
        ); // expected event
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(longAmount, desiredLiqPrice, priceData, "");

        assertEq(tick, expectedTick);
        assertEq(tickVersion, 0);
        assertEq(index, 0);
    }

    // test refunds
    receive() external payable { }
}
