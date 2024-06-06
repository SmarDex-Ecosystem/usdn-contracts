// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";

import { TickMath } from "src/libraries/TickMath.sol";
import { ProtocolAction, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";

/**
 * @custom:feature The rebalancer is triggered after liquidations
 * @custom:background A rebalancer is set and the USDN protocol is initialized with the default params
 */
contract UsdnProtocolRebalancerTriggerTest is UsdnProtocolBaseIntegrationFixture {
    MockChainlinkOnChain public chainlinkGasPriceFeed;
    PositionId public posToLiquidate;
    TickData public tickToLiquidateData;
    uint128 public amountInRebalancer;
    int24 public tickSpacing;

    function setUp() public {
        params = DEFAULT_PARAMS;
        _setUp(params);
        tickSpacing = protocol.getTickSpacing();

        vm.startPrank(DEPLOYER);
        protocol.setFundingSF(0);
        protocol.resetEMA();

        // use a mock for the gas price feed
        chainlinkGasPriceFeed = new MockChainlinkOnChain();
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);
        protocol.setLiquidationRewardsManager(liquidationRewardsManager);
        vm.stopPrank();

        // mint wstEth to the test contract
        (bool success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        wstETH.approve(address(rebalancer), type(uint256).max);

        uint256 messageValue = oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition)
            + protocol.getSecurityDepositValue();

        // deposit assets in the rebalancer
        rebalancer.depositAssets(10 ether, address(this));
        amountInRebalancer += 10 ether;

        // open a position to liquidate and trigger the rebalancer
        posToLiquidate = protocol.initiateOpenPosition{ value: messageValue }(
            2 ether, 1500 ether, address(this), address(this), "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        mockPyth.setPrice(2000e8);
        mockPyth.setLastPublishTime(block.timestamp);

        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateOpenPosition)
        }(address(this), "beef", EMPTY_PREVIOUS_DATA);

        tickToLiquidateData = protocol.getTickData(posToLiquidate.tick);
    }

    /**
     * @custom:scenario The imbalance is high enough so that the rebalancer is triggered after liquidations
     * @custom:given Long positions opened at lower prices
     * @custom:when
     * @custom:then
     */
    function test_rebalancerTrigger() public {
        skip(5 minutes);

        uint128 wstEthPrice = uint128(wstETH.getWstETHByStETH(1280 ether));
        mockPyth.setPrice(1280 ether / 1e10);
        mockPyth.setLastPublishTime(block.timestamp);

        uint128 bonus;
        uint256 totalExpo;
        uint256 longAssetAvailable;
        int256 imbalance;
        uint256 tradingExpoToFill;
        {
            uint128 remainingCollateral =
                uint128(uint256(protocol.getPositionValue(posToLiquidate, wstEthPrice, uint40(block.timestamp))));

            bonus = uint128(uint256(remainingCollateral)) * protocol.getRebalancerBonusBps() / 10_000;
            totalExpo = protocol.getTotalExpo() - tickToLiquidateData.totalExpo;
            uint256 vaultAssetAvailable = uint256(protocol.i_vaultAssetAvailable(wstEthPrice)) + remainingCollateral;
            longAssetAvailable = uint256(protocol.i_longAssetAvailable(wstEthPrice)) - remainingCollateral;
            imbalance = protocol.i_calcLongImbalanceBps(vaultAssetAvailable, longAssetAvailable, totalExpo);
            tradingExpoToFill = (vaultAssetAvailable * uint256(10_000 - protocol.getLongImbalanceTargetBps()) / 10_000)
                - (totalExpo - longAssetAvailable);
        }

        // Sanity check
        assertGt(
            imbalance,
            protocol.getCloseExpoImbalanceLimitBps(),
            "The imbalance is not high enough to trigger the rebalancer, adjust the long positions in the setup"
        );

        HugeUint.Uint512 memory expectedAccumulator = HugeUint.sub(
            protocol.getLiqMultiplierAccumulator(),
            HugeUint.wrap(
                TickMath.getPriceAtTick(
                    posToLiquidate.tick - int24(uint24(tickToLiquidateData.liquidationPenalty)) * tickSpacing
                ) * tickToLiquidateData.totalExpo
            )
        );
        int24 expectedTickWithoutPenalty = protocol.getEffectiveTickForPrice(
            protocol.i_calcLiqPriceFromTradingExpo(wstEthPrice, amountInRebalancer + bonus, tradingExpoToFill),
            wstEthPrice,
            totalExpo - longAssetAvailable,
            expectedAccumulator,
            tickSpacing
        ) + tickSpacing;
        uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            expectedTickWithoutPenalty, wstEthPrice, totalExpo - longAssetAvailable, expectedAccumulator
        );

        _expectEmits(wstEthPrice, amountInRebalancer + bonus, liqPriceWithoutPenalty, expectedTickWithoutPenalty);
        protocol.liquidate{ value: 1 }("beef", 1);

        imbalance = protocol.i_calcLongImbalanceBps(
            protocol.getBalanceVault(), protocol.getBalanceLong(), protocol.getTotalExpo()
        );

        assertLe(
            imbalance, protocol.getLongImbalanceTargetBps(), "The imbalance should be below or equal to the target"
        );
    }

    /// @dev Prepare the expectEmits
    function _expectEmits(uint128 price, uint128 amount, uint128 liqPriceWithoutPenalty, int24 tickWithoutPenalty)
        internal
    {
        uint128 positionTotalExpo = protocol.i_calculatePositionTotalExpo(amount, price, liqPriceWithoutPenalty);

        vm.expectEmit(false, false, false, false);
        emit LiquidatedTick(0, 0, 0, 0, 0);
        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(rebalancer),
            address(rebalancer),
            uint40(block.timestamp),
            positionTotalExpo,
            amount,
            price,
            PositionId(tickWithoutPenalty + (int24(uint24(tickToLiquidateData.liquidationPenalty)) * tickSpacing), 0, 0)
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(
            address(rebalancer),
            address(rebalancer),
            positionTotalExpo,
            price,
            PositionId(tickWithoutPenalty + (int24(uint24(tickToLiquidateData.liquidationPenalty)) * tickSpacing), 0, 0)
        );
    }

    receive() external payable { }
}
