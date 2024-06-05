// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";

/**
 * @custom:feature The rebalancer is triggered after liquidations
 * @custom:background A rebalancer is set and the USDN protocol is initialized with the default params
 */
contract UsdnProtocolRebalancerTriggerTest is UsdnProtocolBaseIntegrationFixture {
    MockChainlinkOnChain public chainlinkGasPriceFeed;
    PositionId public posToLiquidate;

    function setUp() public {
        params = DEFAULT_PARAMS;
        _setUp(params);

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
    }

    /**
     * @custom:scenario The imbalance is high enough so that the rebalancer is triggered after liquidations
     * @custom:given Long positions opened at lower prices
     * @custom:when
     * @custom:then
     */
    function test_rebalancerTrigger() public {
        skip(5 minutes);

        uint128 price = 1280 ether;
        uint128 wstEthPrice = uint128(wstETH.getWstETHByStETH(1280 ether));
        mockPyth.setPrice(int64(int128(price) / 1e10));
        mockPyth.setLastPublishTime(block.timestamp);

        uint256 validationCost = oracleMiddleware.validationCost("beef", ProtocolAction.Liquidation);
        uint40 timestamp = uint40(block.timestamp);
        uint128 remainingCollateral =
            uint128(uint256(protocol.getPositionValue(posToLiquidate, wstEthPrice, timestamp)));

        uint128 bonus = uint128(uint256(remainingCollateral)) * protocol.getRebalancerBonusBps() / 10_000;

        vm.expectEmit(false, false, false, false);
        emit LiquidatedTick(0, 0, 0, 0, 0);
        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(rebalancer),
            address(rebalancer),
            timestamp,
            31_178_357_699_544_775_655,
            10 ether + bonus,
            wstEthPrice,
            PositionId(74_000, 0, 0)
        );

        protocol.liquidate{ value: validationCost }("beef", 1);
    }

    receive() external payable { }
}
