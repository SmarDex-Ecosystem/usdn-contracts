// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";
import { PYTH_ORACLE, CHAINLINK_ORACLE, PYTH_WSTETH_USD } from "test/utils/Constants.sol";
import {
    PYTH_DATA_PRICE,
    PYTH_DATA_CONF,
    PYTH_DATA_TIMESTAMP,
    PYTH_DATA
} from "test/integration/OracleMiddleware/utils/Constants.sol";

import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";

/**
 * @title OracleMiddlewareBaseFixture
 * @dev Utils for testing the oracle middleware
 */
contract OracleMiddlewareBaseFixture is BaseFixture {
    IPyth pyth;
    AggregatorV3Interface chainlinkOnChain;
    OracleMiddleware public oracleMiddleware;

    modifier reSetUp() {
        setUp();
        _;
    }

    function setUp() public virtual {
        pyth = IPyth(PYTH_ORACLE);
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE);
        oracleMiddleware = new OracleMiddleware(address(pyth), PYTH_WSTETH_USD, address(chainlinkOnChain));
    }

    function getMockedPythSignature() internal pure returns (uint256, uint256, uint256, bytes memory) {
        return (PYTH_DATA_PRICE, PYTH_DATA_CONF, PYTH_DATA_TIMESTAMP, PYTH_DATA);
    }

    function getHermesApiSignature(bytes32 feed, uint256 timestamp)
        internal
        returns (uint256, uint256, uint256, bytes memory)
    {
        string[] memory cmds = new string[](4);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "pyth-price";
        cmds[2] = vm.toString(feed);
        cmds[3] = vm.toString(timestamp);
        bytes memory result = vm.ffi(cmds);
        return abi.decode(result, (uint256, uint256, uint256, bytes));
    }

    function getChainlinkPrice() internal view returns (uint256, uint256) {
        (, int256 price,, uint256 timestamp,) = chainlinkOnChain.latestRoundData();
        return (uint256(price), uint256(timestamp));
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
