// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { SET_PROTOCOL_PARAMS_MANAGER } from "../../utils/Constants.sol";
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
        (tickSpacing, amountInRebalancer, posToLiquidate, tickToLiquidateData) = _setUpImbalanced();
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
        skip(5 minutes);

        uint128 wstEthPrice = 1490 ether;
        {
            uint128 ethPrice = uint128(wstETH.getWstETHByStETH(wstEthPrice)) / 1e10;
            mockPyth.setPrice(int64(uint64(ethPrice)));
            mockPyth.setLastPublishTime(block.timestamp);
            wstEthPrice = uint128(wstETH.getStETHByWstETH(ethPrice * 1e10));
        }

        int256 positionValue = protocol.getPositionValue(posToLiquidate, wstEthPrice, uint40(block.timestamp));
        assertGt(positionValue, 0, "position value should be positive");
        uint128 remainingCollateral = uint128(uint256(positionValue));

        uint128 bonus = uint128(uint256(remainingCollateral) * protocol.getRebalancerBonusBps() / BPS_DIVISOR);
        uint256 totalExpo = protocol.getTotalExpo() - tickToLiquidateData.totalExpo;
        uint256 vaultAssetAvailable =
            uint256(protocol.vaultAssetAvailableWithFunding(wstEthPrice, uint40(block.timestamp))) + remainingCollateral;
        uint256 longAssetAvailable =
            uint256(protocol.longAssetAvailableWithFunding(wstEthPrice, uint40(block.timestamp))) - remainingCollateral;
        uint256 tradingExpoToFill = vaultAssetAvailable * BPS_DIVISOR
            / uint256(int256(BPS_DIVISOR) + protocol.getLongImbalanceTargetBps()) - (totalExpo - longAssetAvailable);

        // calculate the state of the liq accumulator after the liquidations
        HugeUint.Uint512 memory expectedAccumulator = HugeUint.sub(
            protocol.getLiqMultiplierAccumulator(),
            HugeUint.wrap(
                TickMath.getPriceAtTick(
                    protocol.i_calcTickWithoutPenalty(posToLiquidate.tick, tickToLiquidateData.liquidationPenalty)
                ) * tickToLiquidateData.totalExpo
            )
        );

        int256 imbalance =
            protocol.i_calcImbalanceCloseBps(int256(vaultAssetAvailable), int256(longAssetAvailable), totalExpo);
        // Sanity check
        assertGt(
            imbalance,
            protocol.getCloseExpoImbalanceLimitBps(),
            "The imbalance is not high enough to trigger the rebalancer, adjust the long positions in the setup"
        );

        (int24 expectedTick,) = protocol.i_getTickFromDesiredLiqPrice(
            protocol.i_calcLiqPriceFromTradingExpo(wstEthPrice, amountInRebalancer + bonus, tradingExpoToFill),
            wstEthPrice,
            totalExpo - longAssetAvailable,
            expectedAccumulator,
            tickSpacing,
            tickToLiquidateData.liquidationPenalty
        );
        uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            protocol.i_calcTickWithoutPenalty(expectedTick, protocol.getLiquidationPenalty()),
            wstEthPrice,
            totalExpo - longAssetAvailable,
            expectedAccumulator
        );
        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        _expectEmits(wstEthPrice, amountInRebalancer, bonus, liqPriceWithoutPenalty, expectedTick, 1);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);

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

        HugeUint.Uint512 memory liqAcc = protocol.getLiqMultiplierAccumulator();
        assertEq(liqAcc.hi, 0, "The hi attribute should be 0");
        assertEq(liqAcc.lo, expectedAccumulator.lo, "The lo attribute should be the expected value");

        assertEq(protocol.getBalanceLong(), longAssetAvailable + amountInRebalancer + bonus);
        assertEq(protocol.getBalanceVault(), vaultAssetAvailable - bonus);
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
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);

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

    receive() external payable { }
}
