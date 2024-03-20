// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    PYTH_DATA_DECIMALS,
    PYTH_DATA_TIMESTAMP,
    PYTH_DATA,
    PYTH_DATA_STETH_PRICE,
    PYTH_DATA_STETH_CONF,
    PYTH_DATA_STETH_DECIMALS,
    PYTH_DATA_STETH
} from "test/integration/Middlewares/utils/Constants.sol";

import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { OracleMiddleware } from "src/OracleMiddleware/OracleMiddleware.sol";
import { WstEthOracleMiddleware } from "src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title ActionsIntegrationFixture
 * @dev required integration actions tests
 */
contract ActionsIntegrationFixture is IOracleMiddlewareErrors {
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

    // all action names
    string[] public actionNames = [
        "None",
        "Initialize",
        "InitiateDeposit",
        "ValidateDeposit",
        "InitiateWithdrawal",
        "ValidateWithdrawal",
        "InitiateOpenPosition",
        "ValidateOpenPosition",
        "InitiateClosePosition",
        "ValidateClosePosition",
        "Liquidation"
    ];
}

contract CommonBaseIntegrationFixture is BaseFixture {
    AggregatorV3Interface internal chainlinkOnChain;

    function _getHermesApiSignature(bytes32 feed, uint256 timestamp)
        internal
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 publishTime_, bytes memory vaa_)
    {
        string[] memory cmds = new string[](4);
        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = "pyth-price";
        cmds[2] = vm.toString(feed);
        cmds[3] = vm.toString(timestamp);
        bytes memory result = vm.ffi(cmds);
        return abi.decode(result, (uint256, uint256, uint256, uint256, bytes));
    }

    function getChainlinkPrice() internal view returns (uint256, uint256) {
        (, int256 price,, uint256 timestamp,) = chainlinkOnChain.latestRoundData();
        return (uint256(price), uint256(timestamp));
    }

    function getHermesApiSignature(bytes32 feed, uint256 timestamp)
        internal
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 publishTime_, bytes memory vaa_)
    {
        return _getHermesApiSignature(feed, timestamp);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}

/**
 * @title OracleMiddlewareBaseIntegrationFixture
 * @dev Utils for testing the oracle middleware
 */
contract OracleMiddlewareBaseIntegrationFixture is CommonBaseIntegrationFixture, ActionsIntegrationFixture {
    IPyth internal pyth;
    OracleMiddleware public oracleMiddleware;

    modifier reSetUp() {
        setUp();
        _;
    }

    function setUp() public virtual {
        pyth = IPyth(PYTH_ORACLE);
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_STETH);
        oracleMiddleware = new OracleMiddleware(address(pyth), PYTH_STETH_USD, address(chainlinkOnChain), 1 hours);
    }

    function getMockedPythSignature()
        internal
        pure
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 publishTime_, bytes memory vaa_)
    {
        return (PYTH_DATA_PRICE, PYTH_DATA_CONF, PYTH_DATA_DECIMALS, PYTH_DATA_TIMESTAMP, PYTH_DATA);
    }
}

/**
 * @title WstethIntegrationFixture
 * @dev Utils for testing the oracle middleware
 */
contract WstethIntegrationFixture is CommonBaseIntegrationFixture, ActionsIntegrationFixture {
    IPyth internal pyth;
    WstEthOracleMiddleware public wstethMiddleware;
    IWstETH public constant WST_ETH = IWstETH(WSTETH);

    modifier reSetUp() virtual {
        setUp();
        _;
    }

    function setUp() public virtual {
        pyth = IPyth(PYTH_ORACLE);
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_STETH);
        wstethMiddleware =
            new WstEthOracleMiddleware(address(pyth), PYTH_STETH_USD, address(chainlinkOnChain), WSTETH, 1 hours);
    }

    function getMockedPythSignature()
        internal
        pure
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 publishTime_, bytes memory vaa_)
    {
        return (
            PYTH_DATA_STETH_PRICE, PYTH_DATA_STETH_CONF, PYTH_DATA_STETH_DECIMALS, PYTH_DATA_TIMESTAMP, PYTH_DATA_STETH
        );
    }

    function stethToWsteth(uint256 amount) public view returns (uint256) {
        return amount * WST_ETH.stEthPerToken() / 1 ether;
    }
}
