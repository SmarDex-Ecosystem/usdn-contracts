// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocolHandler } from "../../unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "../../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { Sdex } from "../../utils/Sdex.sol";
import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";
import { MockLiquidationRewardsManager } from "../mock/MockLiquidationRewardsManager.sol";

import { Setup } from "../Setup.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract FuzzSetup is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */
    function initializeUsdn(
        uint256 depositAmountRand,
        uint256 longAmountRand,
        uint256 priceRand,
        uint256 desiredLiqPriceRand
    ) external {
        // vm.prank(msg.sender);
        Sdex sdex = new Sdex();
        WstETH wsteth = new WstETH();
        wstEthOracleMiddleware = new MockOracleMiddleware();
        // vm.prank(msg.sender);

        liquidationRewardsManager = new MockLiquidationRewardsManager(IWstETH(wsteth), uint256(2 hours + 5 minutes));

        usdn = new Usdn(address(0), address(0));

        // vm.prank(msg.sender);
        rebalancer = new Rebalancer(usdnProtocol);
        usdnProtocol = new UsdnProtocolHandler(
            usdn, sdex, wsteth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR
        );

        // vm.prank(msg.sender);
        usdnProtocol.setRebalancer(rebalancer);

        // vm.prank(msg.sender);
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        // vm.prank(msg.sender);
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));

        // vm.prank(msg.sender);
        wsteth.approve(address(usdnProtocol), depositAmountRand + longAmountRand);

        uint256 _desiredLiqPrice = wstEthOracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), IUsdnProtocolTypes.ProtocolAction.Initialize, abi.encode(priceRand)
        ).price / 2;
        // // vm.prank(msg.sender);
        // try usdnProtocol.initialize(
        //     uint128(depositAmountRand), uint128(longAmountRand), uint128(desiredLiqPriceRand), ""
        // ) {
        //     // Check balances
        //     // assert(address(usdnProtocol).balance == depositAmountRand);
        //     // assert(wsteth.balanceOf(address(usdnProtocol)) == longAmountRand);
        //     // assert(usdn.balanceOf(msg.sender) == usdn.balanceOf(msg.sender));
        // } catch (bytes memory err) {
        //     _checkErrors(err, VALIDATE_OPEN_ERRORS);
        // }

        usdnProtocol.initialize(
            uint128(depositAmountRand), uint128(longAmountRand), uint128(_desiredLiqPrice), abi.encode(priceRand)
        );
    }
}
