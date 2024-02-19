// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { WstETH } from "test/utils/WstEth.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { MockPyth } from "test/unit/OracleMiddleware/utils/MockPyth.sol";
import { MockChainlinkOnChain } from "test/unit/OracleMiddleware/utils/MockChainlinkOnChain.sol";
import { PYTH_WSTETH_USD } from "test/utils/Constants.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";

/**
 * @title ActionsFixture
 * @dev all protocol actions
 */
contract ActionsFixture {
    // all action types
    ProtocolAction[] public actions = [
        ProtocolAction.None,
        ProtocolAction.Initialize,
        ProtocolAction.InitiateDeposit,
        ProtocolAction.ValidateDeposit,
        ProtocolAction.InitiateWithdrawal,
        ProtocolAction.ValidateWithdrawal,
        ProtocolAction.InitiateOpenPosition,
        ProtocolAction.ValidateOpenPosition,
        ProtocolAction.InitiateClosePosition,
        ProtocolAction.ValidateClosePosition,
        ProtocolAction.Liquidation
    ];
}

/**
 * @title OracleMiddlewareBaseFixture
 * @dev Utils for testing the oracle middleware
 */
contract OracleMiddlewareBaseFixture is BaseFixture, ActionsFixture {
    MockPyth internal mockPyth;
    MockChainlinkOnChain internal mockChainlinkOnChain;
    OracleMiddleware public oracleMiddleware;
    uint256 internal chainlinkTimeElapsedLimit = 1 hours;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        mockPyth = new MockPyth();
        mockChainlinkOnChain = new MockChainlinkOnChain();
        oracleMiddleware = new OracleMiddleware(
            address(mockPyth), PYTH_WSTETH_USD, address(mockChainlinkOnChain), chainlinkTimeElapsedLimit
        );
    }

    function test_setUp() public {
        assertEq(address(oracleMiddleware.pyth()), address(mockPyth));
        assertEq(address(oracleMiddleware.priceFeed()), address(mockChainlinkOnChain));

        assertEq(mockPyth.lastPublishTime(), block.timestamp);
        assertEq(mockChainlinkOnChain.lastPublishTime(), block.timestamp);

        /* ----------------------------- Test pyth mock ----------------------------- */
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        PythStructs.PriceFeed[] memory priceFeeds = mockPyth.parsePriceFeedUpdatesUnique{
            value: mockPyth.getUpdateFee(updateData)
        }(updateData, priceIds, 1000, 0);

        assertEq(priceFeeds.length, 1);
        assertEq(priceFeeds[0].price.price, 2000 * 1e8);
        assertEq(priceFeeds[0].price.conf, 20 * 1e8);
        assertEq(priceFeeds[0].price.expo, 8);
        assertEq(priceFeeds[0].price.publishTime, 1000);

        /* ---------------------- Test chainlink on chain mock ---------------------- */
        (, int256 price,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        assertEq(price, 2000 * 1e8);
        assertEq(updatedAt, block.timestamp);
    }
}

/**
 * @title LiquidationRewardsManagerBaseFixture
 * @dev Utils for testing the liquidation rewards manager
 */
contract LiquidationRewardsManagerBaseFixture is BaseFixture {
    MockChainlinkOnChain internal mockChainlinkOnChain;
    WstETH internal wsteth;
    LiquidationRewardsManager internal liquidationRewardsManager;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        mockChainlinkOnChain = new MockChainlinkOnChain();
        wsteth = new WstETH();
        liquidationRewardsManager =
            new LiquidationRewardsManager(address(mockChainlinkOnChain), IWstETH(address(wsteth)), 2 days);
        // Puts the gas at 30 gwei
        mockChainlinkOnChain.setLatestRoundData(1, 30 gwei, block.timestamp, 1);
        vm.txGasPrice(30 gwei);
    }
}

/**
 * @title WstethBaseFixture
 * @dev Utils for testing the wsteth oracle
 */
contract WstethBaseFixture is BaseFixture, ActionsFixture {
    MockPyth internal mockPyth;
    MockChainlinkOnChain internal mockChainlinkOnChain;
    WstEthOracleMiddleware public wstethOracle;
    WstETH public wsteth;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        mockPyth = new MockPyth();
        mockChainlinkOnChain = new MockChainlinkOnChain();
        wsteth = new WstETH();
        wstethOracle =
            new WstEthOracleMiddleware(address(mockPyth), 0, address(mockChainlinkOnChain), address(wsteth), 1 hours);
    }

    function test_setUp() public {
        assertEq(address(wstethOracle.pyth()), address(mockPyth));
        assertEq(address(wstethOracle.priceFeed()), address(mockChainlinkOnChain));

        assertEq(mockPyth.lastPublishTime(), block.timestamp);
        assertEq(mockChainlinkOnChain.lastPublishTime(), block.timestamp);

        /* ----------------------------- Test pyth mock ----------------------------- */
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        PythStructs.PriceFeed[] memory priceFeeds = mockPyth.parsePriceFeedUpdatesUnique{
            value: mockPyth.getUpdateFee(updateData)
        }(updateData, priceIds, 1000, 0);

        assertEq(priceFeeds.length, 1);
        assertEq(priceFeeds[0].price.price, 2000 * 1e8);
        assertEq(priceFeeds[0].price.conf, 20 * 1e8);
        assertEq(priceFeeds[0].price.expo, 8);
        assertEq(priceFeeds[0].price.publishTime, 1000);

        /* ---------------------- Test chainlink on chain mock ---------------------- */
        (, int256 price,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        assertEq(price, 2000 * 1e8);
        assertEq(updatedAt, block.timestamp);
    }

    function stethToWsteth(uint256 amount, uint256 stEthPerToken) public pure returns (uint256) {
        return amount * stEthPerToken / 1 ether;
    }
}
