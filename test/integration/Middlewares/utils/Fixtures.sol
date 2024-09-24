// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

import { CHAINLINK_ORACLE_ETH, PYTH_ETH_USD, PYTH_ORACLE, WSTETH } from "../../../utils/Constants.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import {
    PYTH_DATA_ETH,
    PYTH_DATA_ETH_CONF,
    PYTH_DATA_ETH_DECIMALS,
    PYTH_DATA_ETH_PRICE,
    PYTH_DATA_TIMESTAMP
} from "../utils/Constants.sol";

import { OracleMiddleware } from "../../../../src/OracleMiddleware/OracleMiddleware.sol";
import { WstEthOracleMiddleware } from "../../../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { IWstETH } from "../../../../src/interfaces/IWstETH.sol";
import { IOracleMiddlewareErrors } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IUsdnProtocolTypes } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title ActionsIntegrationFixture
 * @dev Required integration actions tests
 */
contract ActionsIntegrationFixture is IOracleMiddlewareErrors, IUsdnProtocolTypes {
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
        bytes memory result = vmFFIRustCommand("pyth-price", vm.toString(feed), vm.toString(timestamp));

        require(keccak256(result) != keccak256(""), "Rust command returned an error");

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
        require(timestamp <= block.timestamp, "Timestamp cannot be in the future");
        return _getHermesApiSignature(feed, timestamp);
    }
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
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_ETH);
        oracleMiddleware = new OracleMiddleware(address(pyth), PYTH_ETH_USD, address(chainlinkOnChain), 1 hours);
    }

    function getMockedPythSignatureETH()
        internal
        pure
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 publishTime_, bytes memory vaa_)
    {
        return (PYTH_DATA_ETH_PRICE, PYTH_DATA_ETH_CONF, PYTH_DATA_ETH_DECIMALS, PYTH_DATA_TIMESTAMP, PYTH_DATA_ETH);
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
        chainlinkOnChain = AggregatorV3Interface(CHAINLINK_ORACLE_ETH);
        wstethMiddleware =
            new WstEthOracleMiddleware(address(pyth), PYTH_ETH_USD, address(chainlinkOnChain), WSTETH, 1 hours);
    }

    function getMockedPythSignatureETH()
        internal
        pure
        returns (uint256 price_, uint256 conf_, uint256 decimals_, uint256 publishTime_, bytes memory vaa_)
    {
        return (PYTH_DATA_ETH_PRICE, PYTH_DATA_ETH_CONF, PYTH_DATA_ETH_DECIMALS, PYTH_DATA_TIMESTAMP, PYTH_DATA_ETH);
    }

    function stethToWsteth(uint256 amount) public view returns (uint256) {
        return amount * WST_ETH.stEthPerToken() / 1 ether;
    }
}
