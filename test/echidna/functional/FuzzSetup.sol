// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolHandler } from "../../unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "../../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { Sdex } from "../../utils/Sdex.sol";
import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";

import { Setup } from "../Setup.sol";
import { MockLiquidationRewardsManager } from "../mock/MockLiquidationRewardsManager.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";

abstract contract FuzzSetup is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    function initializeUsdn(
        uint256 depositAmountRand,
        uint256 longAmountRand,
        uint256 priceRand,
        uint256 desiredLiqPriceRand
    ) external {
        vm.prank(msg.sender);
        Sdex sdex = new Sdex();
        vm.prank(msg.sender);
        WstETH wsteth = new WstETH();
        vm.prank(msg.sender);
        wstEthOracleMiddleware = new MockOracleMiddleware();
        vm.prank(msg.sender);
        // todo: see if we want to fuse chainlinkElapsedTimeLimit
        liquidationRewardsManager = new MockLiquidationRewardsManager(IWstETH(wsteth), uint256(2 hours + 5 minutes));
        vm.prank(msg.sender);
        usdn = new Usdn(address(0), address(0));
        vm.prank(msg.sender);
        rebalancer = new Rebalancer(usdnProtocol);
        vm.prank(msg.sender);
        usdnProtocol = new UsdnProtocolHandler(
            usdn, sdex, wsteth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR
        );

        vm.prank(msg.sender);
        usdnProtocol.setRebalancer(rebalancer);

        vm.prank(msg.sender);
        bytes32 MINTER_ROLE = usdn.MINTER_ROLE();
        vm.prank(msg.sender);
        usdn.grantRole(MINTER_ROLE, address(usdnProtocol));
        vm.prank(msg.sender);
        bytes32 REBASER_ROLE = usdn.REBASER_ROLE();
        vm.prank(msg.sender);
        usdn.grantRole(REBASER_ROLE, address(usdnProtocol));

        vm.prank(msg.sender);
        wsteth.approve(address(usdnProtocol), depositAmountRand + longAmountRand);

        vm.prank(msg.sender);
        try usdnProtocol.initialize(
            uint128(depositAmountRand), uint128(longAmountRand), uint128(desiredLiqPriceRand), abi.encode(priceRand)
        ) {
            uint256 usdnNoFees = depositAmountRand * priceRand / 10 ** 18; // todo: add fees
            assert(address(usdnProtocol).balance == 0);
            assert(usdn.balanceOf(msg.sender) >= usdnNoFees - usdnNoFees / 10 ** 20); // imperfect estimation
            assert(wsteth.balanceOf(address(usdnProtocol)) == depositAmountRand + longAmountRand);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_OPEN_ERRORS);
        }
    }
}
