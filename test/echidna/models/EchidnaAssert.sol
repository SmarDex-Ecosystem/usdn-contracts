// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockLiquidationRewardsManager } from "../../../src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";
import { MockWstEthOracleMiddleware } from "../../../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../../src/UsdnProtocol/UsdnProtocol.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";

import { SDEX, WSTETH } from "../../utils/Constants.sol";
import { Sdex } from "../../utils/Sdex.sol";

interface IHevm {
    function warp(uint256 newTimestamp) external;
    function deal(address usr, uint256 amt) external;
    function roll(uint256 newNumber) external;
    function load(address where, bytes32 slot) external returns (bytes32);
    function store(address where, bytes32 slot, bytes32 value) external;
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 r, bytes32 v, bytes32 s);
    function addr(uint256 privateKey) external returns (address add);
    function ffi(string[] calldata inputs) external returns (bytes memory result);
    function prank(address newSender) external;
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract Setup is Test {
    address public constant DEPLOYER = address(0x10000);
    address public constant ATTACKER = address(0x20000);
    address public constant FEE_COLLECTOR = address(0x00fee);
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public constant ACCOUNT_ETH_AMOUNT = 100 ether;
    IHevm public constant hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    Permit2TokenBitfield.Bitfield constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);
    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    mapping(address => address[]) public destinationsToken;
    address[2] public validators = [DEPLOYER, ATTACKER];

    Sdex public constant sdex = Sdex(SDEX);
    IWETH public constant weth = IWETH(WETH_ADDRESS);
    IWstETH public constant wstEth = IWstETH(WSTETH);

    MockWstEthOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
    Usdn public usdn;
    UsdnProtocol public usdnProtocol;
    Rebalancer public rebalancer;

    constructor() payable {
        uint256 INIT_DEPOSIT_AMOUNT = 10 ether;
        uint256 INIT_LONG_AMOUNT = 10 ether;

        uint256 _ethAmount =
            (INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT + ACCOUNT_ETH_AMOUNT + 10_000) * wstEth.stEthPerToken() / 1 ether;
        vm.deal(address(this), _ethAmount);
        (bool result,) = WSTETH.call{ value: _ethAmount }("");
        require(result, "WstETH mint failed");

        wstEth.transfer(DEPLOYER, ACCOUNT_ETH_AMOUNT);
        require(wstEth.balanceOf(DEPLOYER) == ACCOUNT_ETH_AMOUNT, "WstETH transfer failed");

        wstEthOracleMiddleware = new MockWstEthOracleMiddleware(
            0x4305FB66699C3B2702D4d05CF36551390A4c69C6,
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
            0x4554480000000000000000000000000000000000000000000000000000000000,
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            WSTETH,
            3720
        );

        liquidationRewardsManager = new MockLiquidationRewardsManager(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C, IWstETH(WSTETH), uint256(2 hours + 5 minutes)
        );

        usdn = new Usdn(address(0), address(0));

        usdnProtocol =
            new UsdnProtocol(usdn, sdex, wstEth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR);

        rebalancer = new Rebalancer(usdnProtocol);

        usdnProtocol.setRebalancer(rebalancer);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        wstEth.approve(address(usdnProtocol), INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT);

        uint256 _desiredLiqPrice = wstEthOracleMiddleware.parseAndValidatePrice(
            bytes32(""), uint128(block.timestamp), IUsdnProtocolTypes.ProtocolAction.Initialize, ""
        ).price / 2;

        usdnProtocol.initialize(uint128(INIT_DEPOSIT_AMOUNT), uint128(INIT_LONG_AMOUNT), uint128(_desiredLiqPrice), "");

        vm.deal(DEPLOYER, ACCOUNT_ETH_AMOUNT);

        destinationsToken[WSTETH] = [DEPLOYER, ATTACKER];
    }
}

contract EchidnaAssert is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    function initiateDeposit(uint128 amountRand, uint8 destRand, uint8 validatorRand) public {
        uint128 amount = uint128(bound(amountRand, 0, wstEth.balanceOf(msg.sender)));

        uint256 destIndex = bound(destRand, 0, destinationsToken[WSTETH].length - 1);
        address dest = destinationsToken[WSTETH][destIndex];

        uint256 validatorIndex = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorIndex]);

        bytes memory priceData = abi.encode(2 ether);

        uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();

        vm.prank(msg.sender);
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amount, dest, validator, NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        );
    }
}
