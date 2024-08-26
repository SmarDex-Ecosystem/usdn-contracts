// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";
import { Setup } from "../Setup.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { Bound } from "../helpers/Bound.sol";

contract FuzzSetup is Setup, Bound {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice PROTCL-13
     */
    function initializeUsdnProtocol(
        uint128 depositAmountRand,
        uint128 longAmountRand,
        uint256 priceRand,
        uint128 desiredLiqPriceRand
    ) external {
        priceRand = bound(priceRand, 0, type(uint128).max);
        if (doesOverflow(depositAmountRand, longAmountRand)) {
            return;
        }
        wsteth.mintAndApprove(
            msg.sender, depositAmountRand + longAmountRand, address(usdnProtocol), depositAmountRand + longAmountRand
        );

        vm.prank(msg.sender);
        try usdnProtocol.initialize(depositAmountRand, longAmountRand, desiredLiqPriceRand, abi.encode(priceRand)) {
            //            assert(address(usdnProtocol).balance == 0);
            //            assert(usdn.balanceOf(msg.sender) >= depositAmountRand * priceRand / 10 ** 18 - 1000);
            //            assert(wsteth.balanceOf(address(usdnProtocol)) == depositAmountRand + longAmountRand);
        } catch (bytes memory err) {
            _checkErrors(err, INITIALIZE_ERRORS);
        }
    }
}
