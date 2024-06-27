// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { SDEX, WSTETH } from "test/utils/Constants.sol";

import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import "../../test/utils/Sdex.sol";
import "../OracleMiddleware/mock/MockLiquidationRewardsManager.sol";
import "../OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import "../Rebalancer/Rebalancer.sol";
import "../Usdn/Usdn.sol";
import "../UsdnProtocol/UsdnProtocol.sol";
import "../interfaces/IWstETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

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
    address public WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IHevm public hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    Sdex public sdex = Sdex(SDEX);

    IWETH public weth = IWETH(WETH_ADDRESS);
    IWstETH public wstEth = IWstETH(WSTETH);

    MockWstEthOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
    Usdn public usdn;
    UsdnProtocol public usdnProtocol;
    Rebalancer public rebalancer;

    address public DEPLOYER = address(0x10000);
    address public ATTACKER = address(0x20000);
    address public FEE_COLLECTOR = address(0x00fee);

    uint256 public ACCOUNT_ETH_AMOUNT = 100 ether;

    constructor() payable {
        uint256 INIT_DEPOSIT_AMOUNT = 10 ether;
        uint256 INIT_LONG_AMOUNT = 10 ether;

        uint256 _ethAmount = (INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT + 10_000) * wstEth.stEthPerToken() / 1 ether;
        vm.deal(address(this), _ethAmount);
        (bool result,) = WSTETH.call{ value: _ethAmount }("");
        require(result, "WstETH mint failed");

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
    }
}

contract EchidnaAssert is Setup {
/* -------------------------------------------------------------------------- */
/*                             Utils                                          */
/* -------------------------------------------------------------------------- */
}
