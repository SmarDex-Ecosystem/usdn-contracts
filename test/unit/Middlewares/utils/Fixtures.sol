// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import { PYTH_ETH_USD, REDSTONE_ETH_USD } from "../../../utils/Constants.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import { OracleMiddlewareHandler } from "../utils/Handler.sol";
import { OracleMiddlewareWithRedstoneHandler } from "../utils/HandlerWithRedstone.sol";
import { MockChainlinkOnChain } from "../utils/MockChainlinkOnChain.sol";
import { MockPyth } from "../utils/MockPyth.sol";

import { ShortOracleMiddleware } from "../../../../src/OracleMiddleware/ShortOracleMiddleware.sol";
import { WstEthOracleMiddleware } from "../../../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { IOracleMiddlewareErrors } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title ActionsFixture
 * @dev All protocol actions
 */
contract ActionsFixture is IOracleMiddlewareErrors, IOracleMiddlewareEvents {
    // all action types
    Types.ProtocolAction[] public actions = [
        Types.ProtocolAction.None,
        Types.ProtocolAction.Initialize,
        Types.ProtocolAction.InitiateDeposit,
        Types.ProtocolAction.ValidateDeposit,
        Types.ProtocolAction.InitiateWithdrawal,
        Types.ProtocolAction.ValidateWithdrawal,
        Types.ProtocolAction.InitiateOpenPosition,
        Types.ProtocolAction.ValidateOpenPosition,
        Types.ProtocolAction.InitiateClosePosition,
        Types.ProtocolAction.ValidateClosePosition,
        Types.ProtocolAction.Liquidation
    ];
}

/**
 * @title OracleMiddlewareBaseFixture
 * @dev Utils for testing the oracle middleware
 */
contract OracleMiddlewareBaseFixture is BaseFixture, ActionsFixture {
    MockPyth internal mockPyth;
    MockChainlinkOnChain internal mockChainlinkOnChain;
    OracleMiddlewareHandler public oracleMiddleware;
    uint256 internal chainlinkTimeElapsedLimit = 1 hours;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        mockPyth = new MockPyth();
        mockChainlinkOnChain = new MockChainlinkOnChain();
        oracleMiddleware = new OracleMiddlewareHandler(
            address(mockPyth), PYTH_ETH_USD, address(mockChainlinkOnChain), chainlinkTimeElapsedLimit
        );
    }

    function test_setUp() public {
        assertEq(address(oracleMiddleware.getPyth()), address(mockPyth));
        assertEq(address(oracleMiddleware.getPriceFeed()), address(mockChainlinkOnChain));

        assertEq(mockPyth.lastPublishTime(), block.timestamp);
        assertEq(mockChainlinkOnChain.latestTimestamp(), block.timestamp);

        /* ----------------------------- Test pyth mock ----------------------------- */
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        PythStructs.PriceFeed[] memory priceFeeds = mockPyth.parsePriceFeedUpdatesUnique{
            value: mockPyth.getUpdateFee(updateData)
        }(updateData, priceIds, 1000, 0);

        assertEq(priceFeeds.length, 1);
        assertEq(priceFeeds[0].price.price, 2000e8);
        assertEq(priceFeeds[0].price.conf, 20e8);
        assertEq(priceFeeds[0].price.expo, -8);
        assertEq(priceFeeds[0].price.publishTime, 1000);

        /* ---------------------- Test chainlink on chain mock ---------------------- */
        (, int256 price,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        assertEq(price, 2000e8);
        assertEq(updatedAt, block.timestamp);
    }
}

/**
 * @title OracleMiddlewareWithRedstoneFixture
 * @dev Utils for testing the oracle middleware with redstone support
 */
contract OracleMiddlewareWithRedstoneFixture is BaseFixture, ActionsFixture {
    MockPyth internal mockPyth;
    MockChainlinkOnChain internal mockChainlinkOnChain;
    OracleMiddlewareWithRedstoneHandler public oracleMiddleware;
    uint256 internal chainlinkTimeElapsedLimit = 1 hours;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        mockPyth = new MockPyth();
        mockChainlinkOnChain = new MockChainlinkOnChain();
        oracleMiddleware = new OracleMiddlewareWithRedstoneHandler(
            address(mockPyth), PYTH_ETH_USD, REDSTONE_ETH_USD, address(mockChainlinkOnChain), chainlinkTimeElapsedLimit
        );
    }

    function test_setUp() public {
        assertEq(address(oracleMiddleware.getPyth()), address(mockPyth));
        assertEq(address(oracleMiddleware.getPriceFeed()), address(mockChainlinkOnChain));

        assertEq(mockPyth.lastPublishTime(), block.timestamp);
        assertEq(mockChainlinkOnChain.latestTimestamp(), block.timestamp);

        /* ----------------------------- Test pyth mock ----------------------------- */
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        PythStructs.PriceFeed[] memory priceFeeds = mockPyth.parsePriceFeedUpdatesUnique{
            value: mockPyth.getUpdateFee(updateData)
        }(updateData, priceIds, 1000, 0);

        assertEq(priceFeeds.length, 1);
        assertEq(priceFeeds[0].price.price, 2000e8);
        assertEq(priceFeeds[0].price.conf, 20e8);
        assertEq(priceFeeds[0].price.expo, -8);
        assertEq(priceFeeds[0].price.publishTime, 1000);

        /* ---------------------- Test chainlink on chain mock ---------------------- */
        (, int256 price,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        assertEq(price, 2000e8);
        assertEq(updatedAt, block.timestamp);
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
        assertEq(address(wstethOracle.getPyth()), address(mockPyth));
        assertEq(address(wstethOracle.getPriceFeed()), address(mockChainlinkOnChain));

        assertEq(mockPyth.lastPublishTime(), block.timestamp);
        assertEq(mockChainlinkOnChain.latestTimestamp(), block.timestamp);

        /* ----------------------------- Test pyth mock ----------------------------- */
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        PythStructs.PriceFeed[] memory priceFeeds = mockPyth.parsePriceFeedUpdatesUnique{
            value: mockPyth.getUpdateFee(updateData)
        }(updateData, priceIds, 1000, 0);

        assertEq(priceFeeds.length, 1);
        assertEq(priceFeeds[0].price.price, 2000e8);
        assertEq(priceFeeds[0].price.conf, 20e8);
        assertEq(priceFeeds[0].price.expo, -8);
        assertEq(priceFeeds[0].price.publishTime, 1000);

        /* ---------------------- Test chainlink on chain mock ---------------------- */
        (, int256 price,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        assertEq(price, 2000e8);
        assertEq(updatedAt, block.timestamp);
    }

    function stethToWsteth(uint256 amount, uint256 stEthPerToken) public pure returns (uint256) {
        return amount * stEthPerToken / 1 ether;
    }
}

/**
 * @title ShortBaseFixture
 * @dev Utils for testing the short oracle middleware
 */
contract ShortBaseFixture is BaseFixture, ActionsFixture {
    MockPyth internal mockPyth;
    MockChainlinkOnChain internal mockChainlinkOnChain;
    ShortOracleMiddleware public shortOracle;
    Usdn public usdn;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        mockPyth = new MockPyth();
        mockChainlinkOnChain = new MockChainlinkOnChain();
        usdn = new Usdn(address(this), address(this));
        usdn.rebase(9e17);
        shortOracle =
            new ShortOracleMiddleware(address(mockPyth), 0, address(mockChainlinkOnChain), address(usdn), 1 hours);
    }

    function test_setUp() public {
        assertEq(address(shortOracle.getPyth()), address(mockPyth));
        assertEq(address(shortOracle.getPriceFeed()), address(mockChainlinkOnChain));

        assertEq(mockPyth.lastPublishTime(), block.timestamp);
        assertEq(mockChainlinkOnChain.latestTimestamp(), block.timestamp);

        /* ----------------------------- Test pyth mock ----------------------------- */
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        PythStructs.PriceFeed[] memory priceFeeds = mockPyth.parsePriceFeedUpdatesUnique{
            value: mockPyth.getUpdateFee(updateData)
        }(updateData, priceIds, 1000, 0);

        assertEq(priceFeeds.length, 1);
        assertEq(priceFeeds[0].price.price, 2000e8);
        assertEq(priceFeeds[0].price.conf, 20e8);
        assertEq(priceFeeds[0].price.expo, -8);
        assertEq(priceFeeds[0].price.publishTime, 1000);

        /* ---------------------- Test chainlink on chain mock ---------------------- */
        (, int256 price,, uint256 updatedAt,) = mockChainlinkOnChain.latestRoundData();
        assertEq(price, 2000e8);
        assertEq(updatedAt, block.timestamp);

        /* ------------------------------ USDN divisor ------------------------------ */
        assertEq(usdn.divisor(), 9e17, "USDN divisor");
    }
}
