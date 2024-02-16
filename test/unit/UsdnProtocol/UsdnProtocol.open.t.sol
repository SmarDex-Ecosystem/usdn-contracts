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
    uint256 internal constant LONG_AMOUNT = 1 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mint(address(this), INITIAL_WSTETH_BALANCE);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario The user initiates an open position action
     * @custom:given The amount of collateral is 1 wstETH and the current price is 2000$
     * @custom:when The user initiates an open position with 1 wstETH and a desired liquidation price of ~1333$ (approx
     * 3x leverage)
     * @custom:then The protocol creates the position and emits the InitiatedOpenPosition event
     * @custom:and the state changes are as expected
     */
    function test_initiateOpenPosition() public {
        uint128 desiredLiqPrice = CURRENT_PRICE * 2 / 3; // leverage approx 3x
        int24 expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);
        uint128 expectedLeverage = uint128(
            (10 ** protocol.LEVERAGE_DECIMALS() * CURRENT_PRICE)
                / (
                    CURRENT_PRICE
                        - protocol.getEffectivePriceForTick(
                            expectedTick - int24(protocol.liquidationPenalty()) * protocol.tickSpacing()
                        )
                )
        );

        uint256 balanceBefore = wstETH.balanceOf(address(this));
        uint256 protocolBalanceBefore = wstETH.balanceOf(address(protocol));
        uint256 totalPositionsBefore = protocol.totalLongPositions();
        uint256 totalExpoBefore = protocol.totalExpo();
        uint256 balanceLongBefore = uint256(protocol.longAssetAvailable(CURRENT_PRICE));

        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this),
            uint40(block.timestamp),
            expectedLeverage,
            uint128(LONG_AMOUNT),
            CURRENT_PRICE,
            expectedTick,
            0,
            0
        ); // expected event
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(uint96(LONG_AMOUNT), desiredLiqPrice, abi.encode(CURRENT_PRICE), "");

        assertEq(tick, expectedTick, "tick number");
        assertEq(tickVersion, 0, "tick version");
        assertEq(index, 0, "index");

        assertEq(wstETH.balanceOf(address(this)), balanceBefore - LONG_AMOUNT, "user wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), protocolBalanceBefore + LONG_AMOUNT, "protocol wstETH balance");
        assertEq(protocol.totalLongPositions(), totalPositionsBefore + 1, "total long positions");
        assertEq(
            protocol.totalExpo(),
            totalExpoBefore + LONG_AMOUNT * expectedLeverage / uint256(10) ** protocol.LEVERAGE_DECIMALS(),
            "protocol total expo"
        );
        assertEq(
            protocol.totalExpoByTick(expectedTick),
            LONG_AMOUNT * expectedLeverage / uint256(10) ** protocol.LEVERAGE_DECIMALS(),
            "total expo in tick"
        );
        assertEq(protocol.positionsInTick(expectedTick), 1, "positions in tick");
        assertEq(protocol.balanceLong(), balanceLongBefore + LONG_AMOUNT, "balance of long side");
    }

    // test refunds
    receive() external payable { }
}
