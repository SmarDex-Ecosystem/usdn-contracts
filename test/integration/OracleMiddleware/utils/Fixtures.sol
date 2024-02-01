// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IOracleMiddlewareErrors, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";
import {
    PYTH_ORACLE,
    CHAINLINK_ORACLE,
    PYTH_WSTETH_USD,
    CHAINLINK_ORACLE_STETH,
    PYTH_STETH_USD,
    WSTETH
} from "test/utils/Constants.sol";

import {
    PYTH_DATA_PRICE,
    PYTH_DATA_CONF,
    PYTH_DATA_TIMESTAMP,
    PYTH_DATA,
    PYTH_DATA_STETH_PRICE,
    PYTH_DATA_STETH_CONF,
    PYTH_DATA_STETH
} from "test/integration/OracleMiddleware/utils/Constants.sol";

import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";

/**
 * @title ActionsIntegrationTests
 * @dev required integration actions tests
 */
contract ActionsIntegrationTests is IOracleMiddlewareErrors {
    // action types for integration tests
    ProtocolAction[] public actions = [
        ProtocolAction.None,
        ProtocolAction.InitiateDeposit,
        ProtocolAction.ValidateDeposit,
        ProtocolAction.ValidateOpenPosition
    ];
}

/**
 * @title OracleMiddlewareBaseFixture
 * @dev Utils for testing the oracle middleware
 */
contract OracleMiddlewareBaseFixture is BaseFixture, ActionsIntegrationTests {
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

/**
 * @title OracleMiddlewareBaseFixture
 * @dev Utils for testing the oracle middleware
 */
contract WstethFixtures is BaseFixture, ActionsIntegrationTests {
    IPyth pyth;
    AggregatorV3Interface chainlinkOnChain;
    WstEthOracleMiddleware public wstethMiddleware;
    IWstETH public constant wsteth = IWstETH(WSTETH);

    modifier reSetUp() {
        setUp();
        _;
    }

    function setUp() public virtual {
        pyth = IPyth(PYTH_ORACLE);
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_STETH);
        wstethMiddleware = new WstEthOracleMiddleware(address(pyth), PYTH_STETH_USD, address(chainlinkOnChain), WSTETH);
    }

    function getMockedPythSignature() internal pure returns (uint256, uint256, uint256, bytes memory) {
        return (PYTH_DATA_STETH_PRICE, PYTH_DATA_STETH_CONF, PYTH_DATA_TIMESTAMP, PYTH_DATA_STETH);
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

    function stethToWsteth(uint256 amount) public view returns (uint256) {
        return amount * wsteth.stEthPerToken() / 1 ether;
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
