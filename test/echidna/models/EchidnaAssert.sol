// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { MockLiquidationRewardsManager } from "../../../src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../../src/UsdnProtocol/UsdnProtocol.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { MockOracleMiddleware } from "../../../test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";

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

    MockOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
    Usdn usdn;
    UsdnProtocol usdnProtocol;
    Rebalancer rebalancer;

    constructor() payable {
        uint256 INIT_DEPOSIT_AMOUNT = 10 ether;
        uint256 INIT_LONG_AMOUNT = 10 ether;
        uint128 PRICE_VALUE = 2000 ether; // 2000 USDN = 1 ETH

        uint256 _ethAmount = (INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT + 10_000) * wsteth.stEthPerToken() / 1 ether;
        vm.deal(address(this), _ethAmount);
        (bool result,) = address(wsteth).call{ value: _ethAmount }("");
        require(result, "WstETH mint failed");

        wstEthOracleMiddleware = new MockOracleMiddleware();

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
            bytes32(""), uint128(block.timestamp), IUsdnProtocolTypes.ProtocolAction.Initialize, abi.encode(PRICE_VALUE)
        ).price / 2;

        // leverage approx 2x
        usdnProtocol.initialize(
            uint128(INIT_DEPOSIT_AMOUNT), uint128(INIT_LONG_AMOUNT), uint128(_desiredLiqPrice), abi.encode(PRICE_VALUE)
        );

        vm.deal(DEPLOYER, ACCOUNT_ETH_AMOUNT);
    }
}

contract EchidnaAssert is Setup {
/* -------------------------------------------------------------------------- */
/*                             Utils                                          */
/* -------------------------------------------------------------------------- */
}
