// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolHandler } from "../../unit/UsdnProtocol/utils/Handler.sol";
import { Sdex } from "../../utils/Sdex.sol";
import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";
import { Setup } from "../Setup.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";

abstract contract FuzzSetup is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    function initializeUsdn(
        uint256 depositAmountRand,
        uint256 longAmountRand,
        uint256 priceRand,
        uint256 desiredLiqPriceRand
    ) external onlyUninitialized {
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
