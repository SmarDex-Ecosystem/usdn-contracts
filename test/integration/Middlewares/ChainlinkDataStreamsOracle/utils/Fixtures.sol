// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

import {
    CHAINLINK_DATA_STREAM_ETH_USD,
    CHAINLINK_ORACLE_ETH,
    CHAINLINK_VERIFIER_PROXY,
    DEPLOYER,
    PYTH_ETH_USD,
    PYTH_ORACLE
} from "../../../../utils/Constants.sol";
import { ActionsIntegrationFixture, CommonBaseIntegrationFixture } from "../../utils/Fixtures.sol";
import { MockFeeManager } from "./MockFeeManager.sol";

import { OracleMiddlewareWithChainlinkDataStreams } from
    "../../../../../src/OracleMiddleware/OracleMiddlewareWithChainlinkDataStreams.sol";

contract ChainlinkDataStreamsFixture is CommonBaseIntegrationFixture, ActionsIntegrationFixture {
    OracleMiddlewareWithChainlinkDataStreams internal oracleMiddleware;

    uint64 internal constant PERCENTAGE_SCALAR = 1e18;

    struct FeeManagerData {
        bool deployMockFeeManager;
        uint64 discountBps;
        uint64 nativeSurchargeBps;
    }

    FeeManagerData internal _params;

    MockFeeManager internal _mockFeeManager;

    IERC20 internal _weth;

    function _setUp(FeeManagerData memory params) internal {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        pyth = IPyth(PYTH_ORACLE);
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_ETH);

        vm.prank(DEPLOYER);
        oracleMiddleware = new OracleMiddlewareWithChainlinkDataStreams(
            address(pyth),
            PYTH_ETH_USD,
            address(chainlinkOnChain),
            1 hours,
            CHAINLINK_VERIFIER_PROXY,
            CHAINLINK_DATA_STREAM_ETH_USD
        );

        if (params.deployMockFeeManager) {
            _mockFeeManager = new MockFeeManager();
            _weth = IERC20(_mockFeeManager.i_nativeAddress());
            _mockFeeManager.updateSubscriberDiscount(
                address(oracleMiddleware),
                CHAINLINK_DATA_STREAM_ETH_USD,
                _mockFeeManager.i_nativeAddress(),
                params.discountBps
            );
            _mockFeeManager.setNativeSurcharge(params.nativeSurchargeBps);

            (, bytes memory proxyVerifierOwnerData) =
                CHAINLINK_VERIFIER_PROXY.staticcall(abi.encodeWithSignature("owner()"));
            address proxyVerifierOwner = abi.decode(proxyVerifierOwnerData, (address));

            vm.prank(proxyVerifierOwner);
            (bool success,) = CHAINLINK_VERIFIER_PROXY.call(
                abi.encodeWithSignature("setFeeManager(address)", address(_mockFeeManager))
            );
            assertTrue(success, "setFeeManager failed");
        }
    }
}
