// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";
import { Setup } from "../Setup.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { InitializableReentrancyGuard } from "../../../src/utils/InitializableReentrancyGuard.sol";

contract FuzzSetup is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice PROTCL-13
     */
    function initializeUsdnProtocol(
        uint256 depositAmountRand,
        uint256 longAmountRand,
        uint256 priceRand,
        uint256 desiredLiqPriceRand
    ) external {
        if (!usdnProtocol.isInitialized()) {
            priceRand = bound(priceRand, 0, type(uint128).max);
            wsteth.mintAndApprove(
                msg.sender,
                depositAmountRand + longAmountRand,
                address(usdnProtocol),
                depositAmountRand + longAmountRand
            );

            vm.prank(msg.sender);
            try usdnProtocol.initialize(
                uint128(depositAmountRand), uint128(longAmountRand), uint128(desiredLiqPriceRand), abi.encode(priceRand)
            ) {
                assert(address(usdnProtocol).balance == 0);
                assert(usdn.balanceOf(msg.sender) >= depositAmountRand * priceRand / 10 ** 18 - 1000);
                assert(wsteth.balanceOf(address(usdnProtocol)) == depositAmountRand + longAmountRand);
            } catch (bytes memory err) {
                _checkErrors(err, INITIALIZE_ERRORS);
            }
        }
    }

    function _checkErrors(bytes memory err, bytes4[][] memory errorsArrays) internal virtual override {
        if (
            bytes4(abi.encodePacked(err))
                == bytes4(InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector)
                && usdnProtocol.isInitialized()
        ) {
            emit log_named_bytes("Should not be initialized: ", err);
            assert(false);
        } else if (
            bytes4(abi.encodePacked(err))
                == bytes4(InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector)
                && usdnProtocol.isInitialized()
        ) {
            emit log_named_bytes("Should not be initialized :", err);
            assert(false);
        } else if (
            bytes4(abi.encodePacked(err))
                != bytes4(InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector)
                && bytes4(abi.encodePacked(err))
                    != bytes4(InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector)
                && !usdnProtocol.isInitialized()
        ) {
            emit log_named_bytes("Uninitialized without expected error:", err);
            assert(false);
        } else if (
            bytes4(abi.encodePacked(err))
                != bytes4(InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector)
                && bytes4(abi.encodePacked(err))
                    != bytes4(InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector)
        ) {
            super._checkErrors(err, errorsArrays);
        }
    }
}
