// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `multiplier` variable of the USDN Protocol
 * @custom:background Given a protocol with ~10 ether of trading expo on either side (approx. equilibrium)
 */
contract TestUsdnProtocolMultiplier is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialLong = 10 ether;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Check that the multiplier increases with positive funding (more long trading expo than vault)
     * @custom:given Twice the long trading expo compared to the vault trading expo
     * @custom:when The funding is positive during 10 days
     * @custom:then The liquidation multiplier increases
     */
    function test_liquidationMultiplierIncrease() public {
        skip(1 hours);
        bytes memory priceData = abi.encode(params.initialPrice);
        // create a long position to have positive funding
        protocol.initiateOpenPosition(
            10 ether, params.initialPrice / 2, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));
        assertGt(protocol.i_longTradingExpo(params.initialPrice), protocol.i_vaultTradingExpo(params.initialPrice));

        // positive funding applies
        skip(10 days);

        // We need to call liquidate to trigger the refresh of the multiplier
        protocol.liquidate(priceData, 0);
        assertGt(protocol.getLiquidationMultiplier(), 10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS());
    }

    /**
     * @custom:scenario Check that the multiplier decreases with negative funding (more vault trading expo than long)
     * @custom:given Twice the vault trading expo compared to the long trading expo
     * @custom:when The funding is negative during 10 days
     * @custom:then The liquidation multiplier decreases
     */
    function test_liquidationMultiplierDecrease() public {
        skip(1 hours);
        bytes memory priceData = abi.encode(params.initialPrice);
        // create a deposit to have negative funding
        protocol.initiateDeposit(10 ether, priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateDeposit(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));
        assertGt(protocol.i_vaultTradingExpo(params.initialPrice), protocol.i_longTradingExpo(params.initialPrice));

        // positive funding applies
        skip(10 days);

        // We need to call liquidate to trigger the refresh of the multiplier
        protocol.liquidate(priceData, 0);
        assertLt(protocol.getLiquidationMultiplier(), 10 ** protocol.LIQUIDATION_MULTIPLIER_DECIMALS());
    }
}
