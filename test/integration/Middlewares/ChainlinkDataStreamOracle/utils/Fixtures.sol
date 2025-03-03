// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

import {
    CHAINLINK_DATA_STREAM_ETH_USD, CHAINLINK_VERIFIER_PROXY, DEPLOYER
} from "../../../../../test/utils/Constants.sol";
import { CHAINLINK_ORACLE_ETH, PYTH_ETH_USD, PYTH_ORACLE } from "../../../../utils/Constants.sol";
import { ActionsIntegrationFixture, CommonBaseIntegrationFixture } from "../../utils/Fixtures.sol";

import { OracleMiddlewareWithChainlinkDataStream } from
    "../../../../../src/OracleMiddleware/OracleMiddlewareWithChainlinkDataStream.sol";

contract ChainlinkDataStreamFixture is CommonBaseIntegrationFixture, ActionsIntegrationFixture {
    OracleMiddlewareWithChainlinkDataStream internal oracleMiddleware;

    function _setUp() internal {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        pyth = IPyth(PYTH_ORACLE);
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_ETH);

        vm.startPrank(DEPLOYER);
        oracleMiddleware = new OracleMiddlewareWithChainlinkDataStream(
            address(pyth),
            PYTH_ETH_USD,
            address(chainlinkOnChain),
            1 hours,
            CHAINLINK_VERIFIER_PROXY,
            CHAINLINK_DATA_STREAM_ETH_USD
        );
        vm.stopPrank();
    }
}
