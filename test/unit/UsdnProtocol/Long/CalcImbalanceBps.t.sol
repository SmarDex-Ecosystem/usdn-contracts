// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The `calcImbalanceBps` function of the long layer
 * @custom:background A deployed USDN protocol initialized at equilibrium with funding enabled
 */
contract TestUsdnProtocolCalcImbalanceBps is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        _setUp(params);
    }

    /**
     * @custom:scenario Calculate the imbalance of the protocol after initialization
     * @custom:when The function is called with the price and timestamp of the initialization
     * @custom:then An imbalance of 0 is returned
     */
    function test_calcImbalanceBpsAtEquilibrium() public view {
        int256 imbalanceBps = protocol.calcImbalanceBps(params.initialPrice, uint128(block.timestamp));

        assertEq(imbalanceBps, 0, "The imbalance should be 0");
    }

    /**
     * @custom:scenario Calculate the imbalance of the protocol with more assets in the vault
     * @custom:given The vault balance being higher than the long balance after a deposit
     * @custom:and Enough time passes for the EMA to catch up with the reality
     * @custom:when The function is called with the price and timestamp of the deposit
     * @custom:then The expected value is returned
     * @custom:and The imbalance should be lower over time
     */
    function test_calcImbalanceBpsMoreInVault() public {
        setUpUserPositionInVault(
            address(this), ProtocolAction.ValidateDeposit, params.initialDeposit / 2, params.initialPrice
        );

        int256 imbalanceBps = protocol.calcImbalanceBps(params.initialPrice, uint128(block.timestamp));

        assertEq(imbalanceBps, 5000, "The imbalance is not the expected value");

        // wait enough time for the EMA to turn around
        skip(5 days);
        protocol.i_applyPnlAndFunding(params.initialPrice, uint128(block.timestamp));
        skip(5 days);
        protocol.i_applyPnlAndFunding(params.initialPrice, uint128(block.timestamp));

        int256 newImbalanceBps = protocol.calcImbalanceBps(params.initialPrice, uint128(block.timestamp));
        assertLt(newImbalanceBps, imbalanceBps, "The imbalance should be lower over time");
    }

    /**
     * @custom:scenario Calculate the imbalance of the protocol with more assets in the long side
     * @custom:given The long balance being higher than the vault balance
     * @custom:when The function is called with the price and timestamp of the open position action
     * @custom:then The expected value is returned
     * @custom:and The imbalance should be lower over time
     */
    function test_calcImbalanceBpsMoreInLong() public {
        OpenParams memory openParams = OpenParams({
            user: address(this),
            untilAction: ProtocolAction.ValidateOpenPosition,
            positionSize: params.initialLong / 10,
            desiredLiqPrice: params.initialPrice / 2,
            price: params.initialPrice
        });
        setUpUserPositionInLong(openParams);

        int256 imbalanceBps = protocol.calcImbalanceBps(params.initialPrice, uint128(block.timestamp));
        assertEq(imbalanceBps, -877, "The imbalance is not the expected value");

        int256 newImbalanceBps = protocol.calcImbalanceBps(params.initialPrice, uint128(block.timestamp + 1 days));
        assertGt(newImbalanceBps, imbalanceBps, "The imbalance should be lower over time");
    }

    /**
     * @custom:scenario Calculate the imbalance of the protocol after the price changes
     * @custom:given Several price changes
     * @custom:when The function is called with each price and the same timestamp
     * @custom:then An imbalance proportional to the price change is returned
     */
    function test_calcImbalanceBpsWithPriceChange() public {
        // we need some imbalance otherwise price has no impact on imbalance
        setUpUserPositionInVault(
            address(this), ProtocolAction.ValidateDeposit, params.initialDeposit / 2, params.initialPrice
        );

        int256 startingImbalanceBps = protocol.calcImbalanceBps(params.initialPrice, uint128(block.timestamp));
        assertEq(startingImbalanceBps, 5000, "The imbalance is not the expected value");

        // +5%
        int256 imbalanceBps = protocol.calcImbalanceBps(params.initialPrice * 105 / 100, uint128(block.timestamp));
        assertEq(imbalanceBps, startingImbalanceBps * 105 / 100, "The imbalance is not the expected value");

        // -5%
        imbalanceBps = protocol.calcImbalanceBps(params.initialPrice * 95 / 100, uint128(block.timestamp));
        assertEq(imbalanceBps, startingImbalanceBps * 95 / 100, "The imbalance is not the expected value");

        // -10%
        imbalanceBps = protocol.calcImbalanceBps(params.initialPrice * 90 / 100, uint128(block.timestamp));
        assertEq(imbalanceBps, startingImbalanceBps * 90 / 100, "The imbalance is not the expected value");
    }
}
