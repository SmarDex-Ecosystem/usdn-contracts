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
        returns (int24 _tick)
    {
        vm.startPrank(user);

        bytes memory priceData = abi.encode(price);

        uint128 liquidationTargetPrice = getLiquidationPrice(price, leverage);
        emit log_named_decimal_uint("liquidationTargetPrice", liquidationTargetPrice, 18);

        _tick = getEffectiveTickForPrice(liquidationTargetPrice);
        emit log_named_decimal_uint("multiplier", _liquidationMultiplier, 38);
        this.initiateOpenPosition(amount, _tick, priceData, "");

        // if auto validate true
        if (autoValidate) {
            this.validateOpenPosition(priceData, priceData);
        }
        vm.warp(1_704_093_400); // 2024-01-01 07:00:00 UTC

        liquidationTargetPrice = getLiquidationPrice(2200 ether, leverage);
        emit log_named_decimal_uint("liquidationTargetPrice", liquidationTargetPrice, 18);
        _tick = getEffectiveTickForPrice(liquidationTargetPrice);
        priceData = abi.encode(2200 ether);
        this.initiateOpenPosition(amount, _tick, priceData, "");

        emit log_named_decimal_uint("multiplier", _liquidationMultiplier, 38);
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
}
