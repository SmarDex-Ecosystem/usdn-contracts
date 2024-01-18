// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The `multiplier` variable of the USDN Protocol
 * @custom:background Given a protocol initialized with 100 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 */
contract TestUsdnProtocolMultiplier is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(
            SetUpParams({
                initialDeposit: 100 ether,
                initialLong: 5 ether,
                initialPrice: 2000 ether,
                initialTimestamp: 1_704_092_400
            })
        );
    }

    /**
     * @custom:scenario A user initiates and validates multiple deposit/position while the price of the asset don't
     * @custom:and change to check the multiplier
     * @custom:when The user opens a long position of 500 wsteth with a leverage of ~2x
     * @custom:then The multiplier should be 1e38 (1st deposit)
     * @custom:when The user deposits 500 wsteth
     * @custom:then The multiplier should be > 1e38
     * @custom:when The user opens a long position of 1 wei to refresh the multiplier
     * @custom:then The multiplier should be < 1e38
     */
    function test_liquidationMultiplier() public {
        vm.deal(USER_1, 100_000 ether);
        wstETH.mint(USER_1, 100_000 ether);
        vm.startPrank(USER_1);
        wstETH.approve(address(protocol), type(uint256).max);

        uint128 liquidationTargetPrice = protocol.getLiquidationPrice(4000 ether, 2_000_000_000);
        int24 tick = protocol.getEffectiveTickForPrice(liquidationTargetPrice);

        protocol.initiateOpenPosition(500 ether, tick, abi.encode(4000 ether), abi.encode(4000 ether));
        protocol.validateOpenPosition(abi.encode(4000 ether), abi.encode(4000 ether));
        assertEq(protocol.liquidationMultiplier(), 1e38);

        // Here, we have longExpo > vaultExpo and fund > 0, so we should have multiplier > 1
        vm.warp(DEFAULT_PARAMS.initialTimestamp + 1 days);
        protocol.initiateDeposit(500 ether, abi.encode(4000 ether), abi.encode(4000 ether));
        protocol.validateDeposit(abi.encode(4000 ether), abi.encode(4000 ether));
        assertGt(protocol.liquidationMultiplier(), 1e38);

        // Here, we have vaultExpo ~= 2*longExpo and fund < 0, so we should have multiplier < 1
        vm.warp(DEFAULT_PARAMS.initialTimestamp + 6 days);
        // We need to initiate a position to trigger the refresh of the multiplier
        protocol.initiateOpenPosition(1, tick, abi.encode(4000 ether), abi.encode(4000 ether));
        assertLt(protocol.liquidationMultiplier(), 1e38);

        vm.stopPrank();
    }
}
