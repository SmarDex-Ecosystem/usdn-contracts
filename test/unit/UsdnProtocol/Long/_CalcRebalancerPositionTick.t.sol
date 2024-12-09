// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constant } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Test the {_calcRebalancerPositionTick} internal function of the long layer
 * @custom:background An initialized usdn protocol contract with 200 ether in the vault
 * @custom:and 100 ether in the long side
 */
contract TestUsdnProtocolLongCalcRebalancerPositionTick is UsdnProtocolBaseFixture {
    using HugeUint for HugeUint.Uint512;

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

        (int24 tick,,) = protocol.i_calcRebalancerPositionTick(
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
            amount * protocol.getMaxLeverage() / 10 ** Constant.LEVERAGE_DECIMALS - amount;
        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, highestUsableTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );

        (int24 tick,,) = protocol.i_calcRebalancerPositionTick(
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
     * to stay above the rebalancer minimum leverage
     * @custom:given The missing trading expo is 1 wei
     * @custom:and An amount of 1 ether
     * @custom:when _calcRebalancerPositionTick is called with too little trading expo to fill
     * @custom:then The result is the expected tick capped to the rebalancer's min leverage
     */
    function test_calcRebalancerPositionTickCappedByTheMinLeverage() public view {
        uint256 rebalancerMaxLeverage = protocol.getMaxLeverage();
        uint256 totalExpo = vaultBalance + longBalance - 1;
        uint128 amount = 1 ether;

        // calculate the lowest usable trading expo to stay above the min leverage
        uint256 lowestUsableTradingExpo =
            amount * Constant.REBALANCER_MIN_LEVERAGE / 10 ** Constant.LEVERAGE_DECIMALS - amount;
        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, lowestUsableTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );

        (int24 tick,,) = protocol.i_calcRebalancerPositionTick(
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
        uint256 highestUsableTradingExpo = amount * rebalancerMaxLeverage / 10 ** Constant.LEVERAGE_DECIMALS - amount;
        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(DEFAULT_PARAMS.initialPrice, amount, highestUsableTradingExpo),
            DEFAULT_PARAMS.initialPrice,
            totalExpo - longBalance,
            protocol.getLiqMultiplierAccumulator(),
            _tickSpacing,
            protocol.getLiquidationPenalty()
        );

        (int24 tick,,) = protocol.i_calcRebalancerPositionTick(
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
     * @custom:scenario Calculate the position tick after the liquidation penalty has changed
     * @custom:given Liquidation penalty is set to 0
     * @custom:and Protocol has one position with 10 ether
     * @custom:when The liquidation penalty is changed to 500
     * @custom:and _calcRebalancerPositionTick is called
     * @custom:then The liquidation penalty should be equal to 0
     * @custom:and The tick should be the same as before the liquidation penalty change
     */
    function test_calcRebalancerPositionTickLiquidationPenaltyChanged() public {
        uint128 amount = 20 ether;
        uint256 totalExpo = 80 ether;
        uint256 balanceLong = 20 ether;
        uint256 balanceVault = 100 ether;

        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(0);

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 40 ether,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice / 2,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        (int24 tickBefore,, uint24 liquidationPenaltyBefore) = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            protocol.getMaxLeverage(),
            totalExpo,
            balanceLong,
            balanceVault,
            protocol.getLiqMultiplierAccumulator()
        );

        assertEq(liquidationPenaltyBefore, 0, "liquidationPenalty should be equal to 0");

        vm.prank(ADMIN);
        protocol.setLiquidationPenalty(500);

        (int24 tickAfter,, uint24 liquidationPenaltyAfter) = protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            protocol.getMaxLeverage(),
            totalExpo,
            balanceLong - 1.5 ether, // we need to change the tradingExpo(totalExpo - balanceLong) to have the same
            // because of the the new liquidation penalty
            balanceVault,
            protocol.getLiqMultiplierAccumulator()
        );

        assertEq(tickBefore, posId.tick, "tickBefore should be equal to posId.tick");
        assertEq(tickAfter, posId.tick, "tickAfter should be equal to posId.tick");
        assertEq(liquidationPenaltyAfter, 0, "liquidationPenalty should not have changed");
    }

    /**
     * @custom:scenario Revert when there is no trading expo to fill
     * @custom:given The trading expo is equal to the vault balance
     * @custom:and An amount of 1 ether
     * @custom:when _calcRebalancerPositionTick is called with no trading expo to fill
     * @custom:then The function reverts with UsdnProtocolInvalidRebalancerTick
     */
    function test_RevertWhen_calcRebalancerPositionTickWithNoTradingExpoToFill() public {
        uint256 rebalancerMaxLeverage = protocol.getMaxLeverage() + 1;
        uint256 totalExpo = vaultBalance + longBalance;
        uint128 amount = 1 ether;

        HugeUint.Uint512 memory accumulator = protocol.getLiqMultiplierAccumulator();

        vm.expectRevert(UsdnProtocolInvalidRebalancerTick.selector);
        protocol.i_calcRebalancerPositionTick(
            DEFAULT_PARAMS.initialPrice,
            amount,
            rebalancerMaxLeverage,
            totalExpo,
            longBalance,
            vaultBalance,
            accumulator
        );
    }
}
