// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { MockLiquidationRewardsManager } from "../../../src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";
import { MockWstEthOracleMiddleware } from "../../../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../../src/UsdnProtocol/UsdnProtocol.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { Sdex } from "../../utils/Sdex.sol";
import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";

contract Setup is Test {
    address public constant DEPLOYER = address(0x10000);
    address public constant ATTACKER = address(0x20000);
    address public constant FEE_COLLECTOR = address(0x00fee);
    uint256 public constant ACCOUNT_ETH_AMOUNT = 100 ether;

    Sdex public immutable sdex = new Sdex();
    Weth public immutable weth = new Weth();
    WstETH public immutable wsteth = new WstETH();

    MockWstEthOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
    Usdn public usdn;
    UsdnProtocol public usdnProtocol;
    Rebalancer public rebalancer;

    constructor() payable {
        uint256 INIT_DEPOSIT_AMOUNT = 10 ether;
        uint256 INIT_LONG_AMOUNT = 10 ether;

        uint256 _ethAmount = (INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT + 10_000) * wsteth.stEthPerToken() / 1 ether;
        vm.deal(address(this), _ethAmount);
        (bool result,) = address(wsteth).call{ value: _ethAmount }("");
        require(result, "WstETH mint failed");

        wstEthOracleMiddleware = new MockWstEthOracleMiddleware(
            0x4305FB66699C3B2702D4d05CF36551390A4c69C6,
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
            0x4554480000000000000000000000000000000000000000000000000000000000,
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            address(wsteth),
            3720
        );

        liquidationRewardsManager = new MockLiquidationRewardsManager(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C, IWstETH(wsteth), uint256(2 hours + 5 minutes)
        );

        usdn = new Usdn(address(0), address(0));

        usdnProtocol =
            new UsdnProtocol(usdn, sdex, wsteth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR);

        rebalancer = new Rebalancer(usdnProtocol);

        usdnProtocol.setRebalancer(rebalancer);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        wsteth.approve(address(usdnProtocol), INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT);

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
