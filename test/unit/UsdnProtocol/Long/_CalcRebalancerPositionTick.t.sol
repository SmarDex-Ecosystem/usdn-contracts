// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the {_calcRebalancerPositionTick} internal function of the long layer
 * @custom:background An initialized usdn protocol contract with 200 ether in the vault
 * @custom:and 100 ether in the long side
 */
contract TestUsdnProtocolLongCalcRebalancerPositionTick is UsdnProtocolBaseFixture {
    uint256 vaultBalance = 200 ether;
    uint256 longBalance = 100 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Calculate the position tick to fill the missing trading expo
     * @custom:given The long total expo is 295 ether
     * @custom:and An amount of 2 ether
     * @custom:when _calcRebalancerPositionTick is called
     * @custom:then The result is the expected tick
     */
    function test_calcRebalancerPositionTick() public view {
        uint256 maxLeverage = protocol.getMaxLeverage();
        uint256 totalExpo = 295 ether;
        uint256 missingTradingExpo = vaultBalance + longBalance - totalExpo;
        uint128 amount = 2 ether;

        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, missingTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );
        expectedTick += _tickSpacing;

        int24 tick = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            maxLeverage,
            totalExpo,
            longBalance,
            vaultBalance,
            protocol.getLiqMultiplierAccumulator()
        );
        assertEq(tick, expectedTick, "The result should be equal to the expected tick");
    }

    /**
     * @custom:scenario Calculate the position tick to use to fill as much trading expo as possible
     * and stay below the protocol max leverage
     * @custom:given The long total expo is 200 ether
     * @custom:and An amount of 1 ether
     * @custom:when _calcRebalancerPositionTick is called with too much trading expo to fill
     * @custom:then The result has been capped to the protocol's max leverage
     */
    function test_calcRebalancerPositionTickCappedByTheProtocolMaxLeverage() public view {
        uint256 rebalancerMaxLeverage = protocol.getMaxLeverage() + 1;
        uint256 totalExpo = 200 ether;
        uint128 amount = 1 ether;

        // calculate the highest usable trading expo to stay below the max leverage
        uint256 highestUsableTradingExpo =
            amount * protocol.getMaxLeverage() / 10 ** protocol.LEVERAGE_DECIMALS() - amount;
        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, highestUsableTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );

        int24 tick = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            rebalancerMaxLeverage,
            totalExpo,
            longBalance,
            vaultBalance,
            protocol.getLiqMultiplierAccumulator()
        );
        assertEq(tick, expectedTick, "The result should be equal to the expected tick");
    }

    /**
     * @custom:scenario Calculate the position tick to use to fill as little trading expo as possible
     * to stay above the protocol min leverage
     * @custom:given The missing trading expo is 1 wei
     * @custom:and An amount of 1 ether
     * @custom:when _calcRebalancerPositionTick is called with too little trading expo to fill
     * @custom:then The result is the expected tick capped to the protocol's min leverage
     */
    function test_calcRebalancerPositionTickCappedByTheMinLeverage() public view {
        uint256 rebalancerMaxLeverage = protocol.getMaxLeverage();
        uint256 totalExpo = vaultBalance + longBalance - 1;
        uint128 amount = 1 ether;

        // calculate the lowest usable trading expo to stay above the min leverage
        uint256 lowestUsableTradingExpo =
            amount * protocol.getMinLeverage() / 10 ** protocol.LEVERAGE_DECIMALS() - amount;
        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, lowestUsableTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );

        int24 tick = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            rebalancerMaxLeverage,
            totalExpo,
            longBalance,
            vaultBalance,
            protocol.getLiqMultiplierAccumulator()
        );
        assertEq(tick, expectedTick, "The result should be equal to the expected tick");
    }

    /**
     * @custom:scenario Calculate the position tick to use to fill as much trading expo as possible
     * and stay below the rebalancer max leverage
     * @custom:given The long total expo is 200 ether
     * @custom:and The rebalancer max leverage is half of the protocol max leverage
     * @custom:and An amount of 1 ether
     * @custom:when _calcRebalancerPositionTick is called with too much trading expo to fill
     * @custom:then The result is the expected tick capped to the rebalancer max's leverage
     */
    function test_calcRebalancerPositionTickCappedByTheRebalancerMaxLeverage() public view {
        uint256 rebalancerMaxLeverage = protocol.getMaxLeverage() / 2;
        uint256 totalExpo = 200 ether;
        uint128 amount = 1 ether;

        // calculate the highest usable trading expo to stay below the max leverage
        uint256 highestUsableTradingExpo = amount * rebalancerMaxLeverage / 10 ** protocol.LEVERAGE_DECIMALS() - amount;
        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, highestUsableTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );

        int24 tick = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            rebalancerMaxLeverage,
            totalExpo,
            longBalance,
            vaultBalance,
            protocol.getLiqMultiplierAccumulator()
        );
        assertEq(tick, expectedTick, "The result should be equal to the expected tick");
    }

    /**
     * @custom:scenario Calculate the position tick to use with a rebalancer max leverage
     * below the protocol min leverage
     * @custom:given The missing trading expo is 1 wei
     * @custom:and A rebalancer max leverage below the protocol min leverage
     * @custom:and An amount of 1 ether
     * @custom:when _calcRebalancerPositionTick is called with a rebalancer leverage lower than
     * the protocol's min leverage
     * @custom:then The result is the expected tick capped by the protocol's min leverage
     */
    function test_calcRebalancerPositionTickCappedByTheRebalancerMaxLeverageBelowTheMinLeverage() public view {
        uint256 rebalancerMaxLeverage = protocol.getMinLeverage() - 1;
        uint256 totalExpo = vaultBalance + longBalance - 1;
        uint128 amount = 1 ether;

        // calculate the lowest usable trading expo to stay above the min leverage
        uint256 lowestUsableTradingExpo =
            amount * protocol.getMinLeverage() / 10 ** protocol.LEVERAGE_DECIMALS() - amount;
        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, lowestUsableTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );

        int24 tick = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            rebalancerMaxLeverage,
            totalExpo,
            longBalance,
            vaultBalance,
            protocol.getLiqMultiplierAccumulator()
        );
        assertEq(tick, expectedTick, "The result should be equal to the expected tick");
    }

    /**
     * @custom:scenario The sentinel value is returned if there is no trading expo to fill
     * @custom:given The trading expo is equal to the vault balance
     * @custom:and An amount of 1 ether
     * @custom:when _calcRebalancerPositionTick is called with no trading expo to fill
     * @custom:then The result is NO_POSITION_TICK sentinel value
     */
    function test_calcRebalancerPositionTickWithNoTradingExpoToFill() public view {
        uint256 rebalancerMaxLeverage = protocol.getMaxLeverage() + 1;
        uint256 totalExpo = vaultBalance + longBalance;
        uint128 amount = 1 ether;

        int24 expectedTick = protocol.NO_POSITION_TICK();
        int24 tick = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            rebalancerMaxLeverage,
            totalExpo,
            longBalance,
            vaultBalance,
            protocol.getLiqMultiplierAccumulator()
        );
        assertEq(tick, expectedTick, "The result should be equal to the expected tick");
    }
}
