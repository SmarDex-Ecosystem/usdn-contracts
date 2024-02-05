// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @custom:feature The `multiplier` variable of the USDN Protocol
 * @custom:background Given a protocol initialized with 100 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 */
contract TestUsdnProtocolMultiplier is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(
            SetUpParams({
                initialDeposit: 100 ether,
                initialLong: 5 ether,
                initialPrice: DEFAULT_PARAMS.initialPrice,
                initialTimestamp: DEFAULT_PARAMS.initialTimestamp,
                initialBlock: DEFAULT_PARAMS.initialBlock
            })
        );
        wstETH.mint(address(this), 100_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);
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
        bytes memory priceData = abi.encode(4000 ether);
        uint128 desiredLiqPrice = 2000 ether;

        protocol.initiateOpenPosition(5 ether, desiredLiqPrice, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        assertEq(protocol.liquidationMultiplier(), 10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS());

        skip(1 days);
        // We need to initiate a position to trigger the refresh of the multiplier
        protocol.initiateDeposit(1, priceData, "");
        protocol.validateDeposit(priceData, "");
        // Here, we have vaultExpo > longExpo and fund > 0, so we should have multiplier > 1
        assertGt(protocol.liquidationMultiplier(), 10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS());

        skip(10 days);
        // We need to initiate a position to trigger the refresh of the multiplier
        protocol.initiateDeposit(1, priceData, "");
        // Here, we have vaultExpo > longExpo and fund < 0, so we should have multiplier < 1
        assertLt(protocol.liquidationMultiplier(), 10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS());
    }
}
