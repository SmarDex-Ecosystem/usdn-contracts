// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { DEPLOYER, SET_PROTOCOL_PARAMS_MANAGER } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IRebalancerEvents } from "../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { HugeUint } from "../../../src/libraries/HugeUint.sol";
import { TickMath } from "../../../src/libraries/TickMath.sol";

/**
 * @custom:feature The rebalancer is triggered after liquidations
 * @custom:background A rebalancer is set and the USDN protocol is initialized with the default params
 */
contract TestUsdnProtocolRebalancerTrigger is UsdnProtocolBaseIntegrationFixture, IRebalancerEvents {
    using HugeUint for HugeUint.Uint512;

    PositionId public posToLiquidate;
    TickData public tickToLiquidateData;
    uint128 public amountInRebalancer;
    int24 public tickSpacing;

    function setUp() public {
        (tickSpacing, amountInRebalancer, posToLiquidate, tickToLiquidateData) =
            _setUpImbalanced(address(this), 10 ether);
        uint256 maxLeverage = protocol.getMaxLeverage();
        vm.startPrank(DEPLOYER);
        rebalancer.setPositionMaxLeverage(maxLeverage);
        vm.stopPrank();
    }

    struct RebalancerTestData {
        uint256 ethPrice;
        uint128 remainingCollateral;
        uint128 bonus;
        uint256 totalExpo;
        uint256 vaultAssetAvailable;
        uint256 liqRewards;
        HugeUint.Uint512 liqAcc;
    }

    /**
     * @custom:scenario The imbalance is high enough so that the rebalancer is triggered after liquidations
     * @custom:given A long position ready to be liquidated
     * @custom:and An imbalance high enough after liquidations to trigger the rebalancer
     * @custom:when The liquidations are executed
     * @custom:then The rebalancer is triggered
     * @custom:and A rebalancer position is created
     */
    function test_rebalancerTrigger() public {
        RebalancerTestData memory data;
        skip(5 minutes);

        uint128 wstEthPrice = 1490 ether;

        data.ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice)) / 1e10;
        mockPyth.setPrice(int64(uint64(data.ethPrice)));
        mockPyth.setLastPublishTime(block.timestamp);
        wstEthPrice = uint128(wstETH.getStETHByWstETH(data.ethPrice * 1e10));

        int256 positionValue = protocol.getPositionValue(posToLiquidate, wstEthPrice, uint40(block.timestamp));
        assertGt(positionValue, 0, "position value should be positive");

        data.remainingCollateral = uint128(uint256(positionValue));
        data.bonus = uint128(uint256(data.remainingCollateral) * protocol.getRebalancerBonusBps() / BPS_DIVISOR);

        data.totalExpo = protocol.getTotalExpo() - tickToLiquidateData.totalExpo;

        data.vaultAssetAvailable = uint256(
            protocol.vaultAssetAvailableWithFunding(wstEthPrice, uint40(block.timestamp))
        ) + data.remainingCollateral;
        uint256 longAssetAvailable =
            protocol.longAssetAvailableWithFunding(wstEthPrice, uint40(block.timestamp)) - data.remainingCollateral;

        uint256 tradingExpoToFill = data.vaultAssetAvailable * BPS_DIVISOR
            / uint256(int256(BPS_DIVISOR) + protocol.getLongImbalanceTargetBps()) - (data.totalExpo - longAssetAvailable);

        // calculate the state of the liq accumulator after the liquidations
        HugeUint.Uint512 memory expectedAccumulator = HugeUint.sub(
            protocol.getLiqMultiplierAccumulator(),
            HugeUint.wrap(
                TickMath.getPriceAtTick(
                    protocol.i_calcTickWithoutPenalty(posToLiquidate.tick, tickToLiquidateData.liquidationPenalty)
                ) * tickToLiquidateData.totalExpo
            )
        );

        int256 imbalance = protocol.i_calcImbalanceCloseBps(
            int256(data.vaultAssetAvailable), int256(longAssetAvailable), data.totalExpo
        );
        assertGt(
            imbalance,
            protocol.getCloseExpoImbalanceLimitBps(),
            "The imbalance is not high enough to trigger the rebalancer, adjust the long positions in the setup"
        );

        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(wstEthPrice, amountInRebalancer + data.bonus, tradingExpoToFill),
            wstEthPrice,
            data.totalExpo - longAssetAvailable,
            expectedAccumulator,
            tickSpacing,
            tickToLiquidateData.liquidationPenalty
        );
        uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            protocol.i_calcTickWithoutPenalty(expectedTick, protocol.getLiquidationPenalty()),
            wstEthPrice,
            data.totalExpo - longAssetAvailable,
            expectedAccumulator
        );

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);

        data.liqRewards = _calcRewards(int256(uint256(data.remainingCollateral)), wstEthPrice);

        _expectEmits(wstEthPrice, amountInRebalancer, data.bonus, liqPriceWithoutPenalty, expectedTick, 1);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA);

        imbalance = protocol.i_calcImbalanceCloseBps(
            int256(protocol.getBalanceVault()), int256(protocol.getBalanceLong()), protocol.getTotalExpo()
        );

        assertLe(
            imbalance, protocol.getLongImbalanceTargetBps(), "The imbalance should be below or equal to the target"
        );

        // get the position that has been created
        (Position memory pos,) = protocol.getLongPosition(PositionId(expectedTick, 0, 0));

        // update the expected liquidation accumulator
        uint256 unadjustedTickPrice = TickMath.getPriceAtTick(
            protocol.i_calcTickWithoutPenalty(expectedTick, tickToLiquidateData.liquidationPenalty)
        );
        expectedAccumulator = expectedAccumulator.add(HugeUint.wrap(unadjustedTickPrice * pos.totalExpo));

        data.liqAcc = protocol.getLiqMultiplierAccumulator();
        assertEq(data.liqAcc.hi, 0, "The hi attribute should be 0");
        assertEq(data.liqAcc.lo, expectedAccumulator.lo, "The lo attribute should be the expected value");

        assertEq(protocol.getBalanceLong(), longAssetAvailable + amountInRebalancer + data.bonus, "balance long");
        assertEq(protocol.getBalanceVault(), data.vaultAssetAvailable - data.bonus - data.liqRewards, "balance vault");
    }

    /**
     * @custom:scenario The imbalance is high enough so that the rebalancer tries to trigger but can't because of the
     * zero close limit
     * @custom:given A long position ready to be liquidated
     * @custom:and An imbalance high enough after a liquidation to trigger the rebalancer
     * @custom:when The liquidation is executed
     * @custom:then The rebalancer is not triggered
     */
    function test_rebalancerTrigger_zeroLimit() public {
        vm.startPrank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setExpoImbalanceLimits(
            uint256(protocol.getOpenExpoImbalanceLimitBps()),
            uint256(protocol.getDepositExpoImbalanceLimitBps()),
            uint256(protocol.getWithdrawalExpoImbalanceLimitBps()),
            0,
            0,
            0
        );
        vm.stopPrank();

        skip(5 minutes);

        uint128 wstEthPrice = 1490 ether;
        {
            uint128 ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice)) / 1e10;
            mockPyth.setPrice(int64(uint64(ethPrice)));
            mockPyth.setLastPublishTime(block.timestamp);
            wstEthPrice = uint128(wstETH.getStETHByWstETH(ethPrice * 1e10));
        }

        uint256 pendingAssets = rebalancer.getPendingAssetsAmount();
        uint256 posVersion = rebalancer.getPositionVersion();

        // Sanity check
        assertEq(0, protocol.getCloseExpoImbalanceLimitBps(), "The close limit should be zero");

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);

        vm.expectEmit(false, false, false, false);
        emit LiquidatedTick(0, 0, 0, 0, 0);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA);

        assertEq(rebalancer.getPendingAssetsAmount(), pendingAssets);
        assertEq(rebalancer.getPositionVersion(), posVersion);
    }

    /// @dev Prepare the expectEmits
    function _expectEmits(
        uint128 price,
        uint128 amount,
        uint128 bonus,
        uint128 liqPriceWithoutPenalty,
        int24 tick,
        uint128 newPositionVersion
    ) internal {
        uint128 positionTotalExpo = protocol.i_calcPositionTotalExpo(amount + bonus, price, liqPriceWithoutPenalty);
        uint256 defaultAccMultiplier = rebalancer.MULTIPLIER_FACTOR();
        PositionId memory expectedPositionId = PositionId(tick, 0, 0);

        vm.expectEmit(false, false, false, false);
        emit LiquidatedTick(0, 0, 0, 0, 0);
        vm.expectEmit(address(protocol));
        emit InitiatedOpenPosition(
            address(rebalancer),
            address(rebalancer),
            uint40(block.timestamp),
            positionTotalExpo,
            amount + bonus,
            price,
            expectedPositionId
        );
        vm.expectEmit(address(protocol));
        emit ValidatedOpenPosition(
            address(rebalancer), address(rebalancer), positionTotalExpo, price, expectedPositionId
        );
        vm.expectEmit(address(rebalancer));
        emit PositionVersionUpdated(newPositionVersion, defaultAccMultiplier, amount, expectedPositionId);
    }

    /**
     * @dev Calculate the rewards for the liquidation
     * @param remainingCollateral The remaining collateral after the liquidation
     * @param wstEthPrice The price of the asset
     */
    function _calcRewards(int256 remainingCollateral, uint128 wstEthPrice) internal view returns (uint256 rewards_) {
        uint256 tradingExpoWithFunding = protocol.longTradingExpoWithFunding(wstEthPrice, uint40(block.timestamp));
        uint128 tickPrice = protocol.getEffectivePriceForTick(
            posToLiquidate.tick, wstEthPrice, tradingExpoWithFunding, protocol.getLiqMultiplierAccumulator()
        );
        uint128 tickPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            protocol.i_calcTickWithoutPenalty(posToLiquidate.tick, tickToLiquidateData.liquidationPenalty),
            wstEthPrice,
            tradingExpoWithFunding,
            protocol.getLiqMultiplierAccumulator()
        );

        LiqTickInfo[] memory liquidatedTicks = new LiqTickInfo[](1);
        liquidatedTicks[0] = LiqTickInfo({
            totalPositions: tickToLiquidateData.totalPos,
            totalExpo: tickToLiquidateData.totalExpo,
            remainingCollateral: int256(uint256(remainingCollateral)),
            tickPrice: tickPrice,
            priceWithoutPenalty: tickPriceWithoutPenalty
        });

        rewards_ = liquidationRewardsManager.getLiquidationRewards(
            liquidatedTicks, wstEthPrice, false, RebalancerAction.Opened, ProtocolAction.None, "", ""
        );
    }

    receive() external payable { }
}
