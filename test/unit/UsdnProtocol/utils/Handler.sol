// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";

import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolHandler is UsdnProtocol {
    uint128 public constant wstethInitialPrice = 2630 ether;

    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing)
        UsdnProtocol(usdn, asset, oracleMiddleware, tickSpacing)
    { }

    function mockInitiateOpenPosition(bool autoValidate, address user, uint128 price, uint40 leverage, uint96 amount)
        external
        returns (int24 tick)
    {
        vm.startPrank(user);
        _asset.approve(address(this), type(uint256).max);

        bytes memory priceData = abi.encode(price);
        uint128 liquidationTargetPrice = getLiquidationPrice(price, leverage);

        tick = getEffectiveTickForPrice(liquidationTargetPrice);
        this.initiateOpenPosition(amount, tick, priceData, "");

        // if auto validate true
        if (autoValidate) {
            this.validateOpenPosition(priceData, priceData);
        }
        emit log_named_decimal_int("vault expo", _vaultTradingExpo(price), 18);
        emit log_named_decimal_int("long expo", _longTradingExpo(price), 18);
        // vm.stopPrank();
        // vm.warp(1_704_179_700); // 2024-01-01 07:00:00 UTC

        // priceData = abi.encode(4000 ether);
        // vm.prank(address(0x2222222222222222222222222222222222222222));
        // this.initiateOpenPosition(100, tick, priceData, "");

        // vm.warp(1_705_043_700);
        // vm.prank(address(0x3333333333333333333333333333333333333333));
        // this.initiateOpenPosition(100, tick, priceData, priceData);
    }

    function validationDeadline() external view returns (uint256) {
        return _validationDeadline;
    }

    function getUserPendingAction(address user) external returns (PendingAction memory) {
        return _getPendingAction(user, false); // do not clear
    }

    function balanceVault() external view returns (uint256) {
        return _balanceVault;
    }

    function vaultAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return _vaultAssetAvailable(currentPrice);
    }

    function liquidationMultiplier() external view returns (uint256) {
        return _liquidationMultiplier;
    }
}
