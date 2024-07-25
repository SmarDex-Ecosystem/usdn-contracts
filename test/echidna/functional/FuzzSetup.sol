// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolHandler } from "../../unit/UsdnProtocol/utils/Handler.sol";
import { Setup } from "../Setup.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";

contract FuzzSetup is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */
    function deployUsdn() external {
        try new UsdnProtocolHandler(
            usdn, sdex, wsteth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR
        ) returns (UsdnProtocolHandler _usdnProtocol) {
            usdnProtocol = _usdnProtocol;
            rebalancer = new Rebalancer(usdnProtocol);

            usdnProtocol.setRebalancer(rebalancer);

            usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
            usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_OPEN_ERRORS);
        }
    }

    function initializeUsdn(uint256 depositAmountRand, uint256 longAmountRand, uint256 desiredLiqPriceRand) external {
        wsteth.approve(address(usdnProtocol), depositAmountRand + longAmountRand);

        try usdnProtocol.initialize(
            uint128(depositAmountRand), uint128(longAmountRand), uint128(desiredLiqPriceRand), ""
        ) { } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_OPEN_ERRORS);
        }
    }
}
